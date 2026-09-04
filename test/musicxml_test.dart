import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metro_sound/services/musicxml.dart';

const _doc = '''
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="3.1">
  <work><work-title>Study in G</work-title></work>
  <part-list><score-part id="P1"/></part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>2</divisions>
        <time><beats>3</beats><beat-type>4</beat-type></time>
      </attributes>
      <direction>
        <direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>96</per-minute></metronome></direction-type>
        <sound tempo="96"/>
      </direction>
      <note><pitch><step>G</step><octave>4</octave></pitch><duration>2</duration><voice>1</voice></note>
      <note><pitch><step>F</step><alter>1</alter><octave>4</octave></pitch><duration>1</duration><voice>1</voice></note>
      <note><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice></note>
      <note><rest/><duration>2</duration><voice>1</voice></note>
    </measure>
    <measure number="2">
      <note><pitch><step>A</step><octave>4</octave></pitch><duration>4</duration><voice>1</voice><tie type="start"/></note>
      <note><pitch><step>A</step><octave>4</octave></pitch><duration>2</duration><voice>1</voice><tie type="stop"/></note>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>2</duration><voice>2</voice></note>
    </measure>
  </part>
</score-partwise>
''';

void main() {
  test('parses pitches, rhythm, rests, ties, tempo, and time signature', () {
    final s = parseMusicXml(_doc);
    expect(s.title, 'Study in G');
    expect(s.bpm, 96);
    expect(s.beatsPerBar, 3);
    expect(s.denominator, 4);
    // G4 quarter, F#4 eighth, G4 eighth, rest quarter, A4 tied whole = 3 beats.
    // The voice-2 C5 is skipped.
    expect(s.notes.map((n) => n.midi).toList(), [67, 66, 67, null, 69]);
    expect(s.notes.map((n) => n.beats).toList(), [1.0, 0.5, 0.5, 1.0, 3.0]);
  });

  test('reads compressed .mxl via its container manifest', () {
    final zip = Archive()
      ..addFile(ArchiveFile.string(
          'META-INF/container.xml',
          '<container><rootfiles>'
          '<rootfile full-path="score.xml"/>'
          '</rootfiles></container>'))
      ..addFile(ArchiveFile.string('score.xml', _doc));
    final bytes = Uint8List.fromList(ZipEncoder().encode(zip));
    final s = parseMusicXmlBytes(bytes, filename: 'study.mxl');
    expect(s.title, 'Study in G');
    expect(s.notes.length, 5);
  });

  test('rejects files with no playable notes', () {
    const empty = '<score-partwise><part id="P1"><measure number="1">'
        '<note><rest/><duration>4</duration></note>'
        '</measure></part></score-partwise>';
    expect(() => parseMusicXml(empty), throwsA(isA<MusicXmlException>()));
  });

  test('rejects non-MusicXML input', () {
    expect(
      () => parseMusicXmlBytes(Uint8List.fromList(utf8.encode('hello')),
          filename: 'x.xml'),
      throwsA(isA<MusicXmlException>()),
    );
  });
}
