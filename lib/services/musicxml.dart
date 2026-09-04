import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'score_synth.dart';

/// Minimal MusicXML → [Score] importer for monophonic scores — the handoff
/// format a future OMR stage (or MuseScore/Audiveris transcription) produces.
///
/// Supported: score-partwise, first part only, first voice only; pitch
/// (step/alter/octave), rests, durations via `divisions`, tied notes (merged),
/// time signature, tempo from `<sound tempo>` or `<metronome><per-minute>`.
/// Chord extra notes, grace notes, and other voices are skipped — the renderer
/// is monophonic anyway.

class MusicXmlException implements Exception {
  final String message;
  MusicXmlException(this.message);
  @override
  String toString() => message;
}

/// Parse raw file bytes: plain `.xml`/`.musicxml`, or compressed `.mxl` (a zip
/// whose META-INF/container.xml names the root score file).
Score parseMusicXmlBytes(Uint8List bytes, {required String filename}) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.mxl')) {
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw MusicXmlException('Not a valid .mxl (zip) file.');
    }
    String? rootPath;
    final container = zip.findFile('META-INF/container.xml');
    if (container != null) {
      try {
        final doc = XmlDocument.parse(utf8.decode(container.content));
        rootPath = doc
            .findAllElements('rootfile')
            .firstOrNull
            ?.getAttribute('full-path');
      } catch (_) {}
    }
    final root = (rootPath != null ? zip.findFile(rootPath) : null) ??
        zip.files.where((f) {
          final n = f.name.toLowerCase();
          return f.isFile &&
              !n.startsWith('meta-inf/') &&
              (n.endsWith('.xml') || n.endsWith('.musicxml'));
        }).firstOrNull;
    if (root == null) {
      throw MusicXmlException('No score found inside the .mxl file.');
    }
    return parseMusicXml(utf8.decode(root.content), fallbackTitle: filename);
  }
  return parseMusicXml(utf8.decode(bytes), fallbackTitle: filename);
}

Score parseMusicXml(String source, {String? fallbackTitle}) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(source);
  } catch (e) {
    throw MusicXmlException('Not a valid MusicXML file.');
  }
  final partwise = doc.findAllElements('score-partwise').firstOrNull;
  if (partwise == null) {
    throw MusicXmlException(
        'Only score-partwise MusicXML is supported (this file is not one).');
  }
  final part = partwise.findElements('part').firstOrNull;
  if (part == null) throw MusicXmlException('The score has no parts.');

  final title = partwise
          .findAllElements('work-title')
          .firstOrNull
          ?.innerText
          .trim()
          .nonEmpty ??
      partwise
          .findAllElements('movement-title')
          .firstOrNull
          ?.innerText
          .trim()
          .nonEmpty ??
      fallbackTitle ??
      'Imported score';

  var divisions = 1.0; // duration units per quarter note
  var beatsPerBar = 4;
  var denominator = 4;
  int? bpm;
  String? voice; // lock onto the first voice we see
  final notes = <ScoreNote>[];
  var lastTiedStart = false;

  double? readDouble(XmlElement parent, String name) =>
      double.tryParse(parent.findElements(name).firstOrNull?.innerText ?? '');

  for (final measure in part.findElements('measure')) {
    for (final el in measure.childElements) {
      switch (el.name.local) {
        case 'attributes':
          divisions = readDouble(el, 'divisions') ?? divisions;
          final time = el.findElements('time').firstOrNull;
          if (time != null) {
            beatsPerBar = readDouble(time, 'beats')?.round() ?? beatsPerBar;
            denominator = readDouble(time, 'beat-type')?.round() ?? denominator;
          }
        case 'sound':
          bpm ??= double.tryParse(el.getAttribute('tempo') ?? '')?.round();
        case 'direction':
          bpm ??= double.tryParse(
                  el.findAllElements('per-minute').firstOrNull?.innerText ?? '')
              ?.round();
          bpm ??= double.tryParse(el
                      .findAllElements('sound')
                      .firstOrNull
                      ?.getAttribute('tempo') ??
                  '')
              ?.round();
        case 'note':
          if (el.findElements('grace').isNotEmpty) continue;
          if (el.findElements('chord').isNotEmpty) continue; // keep top voice
          final noteVoice = el.findElements('voice').firstOrNull?.innerText;
          voice ??= noteVoice;
          if (noteVoice != null && noteVoice != voice) continue;

          final durUnits = readDouble(el, 'duration');
          if (durUnits == null || durUnits <= 0) continue;
          // duration/divisions is in quarter notes; Score counts beats in the
          // time signature's denominator unit.
          final beats = durUnits / divisions * (denominator / 4.0);

          final pitch = el.findElements('pitch').firstOrNull;
          if (pitch == null) {
            notes.add(ScoreNote.rest(beats));
            lastTiedStart = false;
            continue;
          }
          final step = pitch.findElements('step').firstOrNull?.innerText ?? '';
          const semis = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
          final semi = semis[step];
          final octave = readDouble(pitch, 'octave')?.round();
          if (semi == null || octave == null) continue;
          final alter = readDouble(pitch, 'alter')?.round() ?? 0;
          final midi = (octave + 1) * 12 + semi + alter;

          final tieStop = el
              .findElements('tie')
              .any((t) => t.getAttribute('type') == 'stop');
          if (tieStop && lastTiedStart && notes.isNotEmpty) {
            final prev = notes.last;
            if (prev.midi == midi) {
              notes[notes.length - 1] = ScoreNote(midi, prev.beats + beats);
              lastTiedStart = el
                  .findElements('tie')
                  .any((t) => t.getAttribute('type') == 'start');
              continue;
            }
          }
          notes.add(ScoreNote(midi, beats));
          lastTiedStart = el
              .findElements('tie')
              .any((t) => t.getAttribute('type') == 'start');
      }
    }
  }

  if (notes.every((n) => n.midi == null)) {
    throw MusicXmlException('The score contains no playable notes.');
  }
  return Score(
    title: title,
    bpm: (bpm ?? 80).clamp(20, 300),
    beatsPerBar: beatsPerBar.clamp(1, 16),
    denominator: denominator,
    notes: notes,
  );
}

extension on String {
  String? get nonEmpty => isEmpty ? null : this;
}
