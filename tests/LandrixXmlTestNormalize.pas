{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Tests for LandrixXmlNormalize: a committed sample in the format of the
  Unicode file NormalizationTest.txt (source;NFC;NFD;NFKC;NFKD as hex
  code points, expected values from Python's unicodedata) and, when
  tools/fetch-unicode-tests.py has downloaded it into
  tests/data/unicode-suite/, the whole file NormalizationTest.txt 15.0.0
  (skipped silently otherwise). }

unit LandrixXmlTestNormalize;

{$I LandrixXml.inc}

interface

procedure Register;

implementation

uses
  SysUtils,
  Classes,
  LandrixXmlBase,
  LandrixXmlUnicode,
  LandrixXmlNormalize,
  LandrixXmlTestFramework;

type
  TColumns = array[0..4] of string;

const
  Sample: array[0..34] of string = (
    ';;;;',
    '0061 0062 0063;0061 0062 0063;0061 0062 0063;0061 0062 0063;0061 0062 0063',
    '00E4;00E4;0061 0308;00E4;0061 0308',
    '0041 0308;00C4;0041 0308;00C4;0041 0308',
    '00C5;00C5;0041 030A;00C5;0041 030A',
    '212B;00C5;0041 030A;00C5;0041 030A',
    '0041 030A 0301;01FA;0041 030A 0301;01FA;0041 030A 0301',
    { NFD and NFKD differ in the first code point }
    '1E9B 0323;1E9B 0323;017F 0323 0307;1E69;0073 0323 0307',
    '0385;0385;00A8 0301;0020 0308 0301;0020 0308 0301',
    { the longest decomposition }
    'FDFA;FDFA;FDFA;0635 0644 0649 0020 0627 0644 0644 0647 0020 0639 0644 064A 0647 0020 0648 0633 0644 0645;' +
      '0635 0644 0649 0020 0627 0644 0644 0647 0020 0639 0644 064A 0647 0020 0648 0633 0644 0645',
    { composition exclusions: a singleton, a script exclusion, non-starter
      decompositions }
    '2126;03A9;03A9;03A9;03A9',
    '0958;0915 093C;0915 093C;0915 093C;0915 093C',
    '0F73;0F71 0F72;0F71 0F72;0F71 0F72;0F71 0F72',
    '0344;0308 0301;0308 0301;0308 0301;0308 0301',
    'FB01;FB01;FB01;0066 0069;0066 0069',
    { Hangul }
    'AC00;AC00;1100 1161;AC00;1100 1161',
    'AC01;AC01;1100 1161 11A8;AC01;1100 1161 11A8',
    '1100 1161 11A8;AC01;1100 1161 11A8;AC01;1100 1161 11A8',
    '1100 1161;AC00;1100 1161;AC00;1100 1161',
    'AC00 11A8;AC01;1100 1161 11A8;AC01;1100 1161 11A8',
    { reordering, composition across a lower class, blocking }
    '0061 0302 0323;1EAD;0061 0323 0302;1EAD;0061 0323 0302',
    '0073 0323 0307;1E69;0073 0323 0307;1E69;0073 0323 0307',
    '1E0A 0323;1E0C 0307;0044 0323 0307;1E0C 0307;0044 0323 0307',
    '0061 05AE 0300 0315 0062;00E0 05AE 0315 0062;0061 05AE 0300 0315 0062;00E0 05AE 0315 0062;0061 05AE 0300 0315 0062',
    '0061 0300 0300;00E0 0300;0061 0300 0300;00E0 0300;0061 0300 0300',
    '0301 0061;0301 0061;0301 0061;0301 0061;0301 0061',
    '0041 0300 0041 0301;00C0 00C1;0041 0300 0041 0301;00C0 00C1;0041 0300 0041 0301',
    { supplementary planes, unassigned and noncharacters }
    '11099 110BA;1109A;11099 110BA;1109A;11099 110BA',
    '00A0;00A0;00A0;0020;0020',
    '0378;0378;0378;0378;0378',
    'FFFE;FFFE;FFFE;FFFE;FFFE',
    '10FFFD;10FFFD;10FFFD;10FFFD;10FFFD',
    'E0100;E0100;E0100;E0100;E0100',
    '0915 093C;0915 093C;0915 093C;0915 093C;0915 093C',
    { a run of non-starters longer than the insertion sort handles }
    '0061 0301 0316 0301 0316 0301 0316 0301 0316 0301 0316 0301 0316 0301 0316 0301 0316 0301 0316 0301 0316 0062;' +
      '00E1 0316 0316 0316 0316 0316 0316 0316 0316 0316 0316 0301 0301 0301 0301 0301 0301 0301 0301 0301 0062;' +
      '0061 0316 0316 0316 0316 0316 0316 0316 0316 0316 0316 0301 0301 0301 0301 0301 0301 0301 0301 0301 0301 0062;' +
      '00E1 0316 0316 0316 0316 0316 0316 0316 0316 0316 0316 0301 0301 0301 0301 0301 0301 0301 0301 0301 0062;' +
      '0061 0316 0316 0316 0316 0316 0316 0316 0316 0316 0316 0301 0301 0301 0301 0301 0301 0301 0301 0301 0301 0062');

  Forms: array[0..3] of TLandrixXmlNormalizationForm = (xnfNfc, xnfNfd, xnfNfkc, xnfNfkd);
  FormNames: array[0..3] of string = ('NFC', 'NFD', 'NFKC', 'NFKD');

function SuiteFile: string;
begin
  Result := RepositoryRoot + 'tests' + PathDelim + 'data' + PathDelim +
    'unicode-suite' + PathDelim + 'NormalizationTest.txt';
end;

function HexValue(const S: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Length(S) do
    case S[I] of
      '0'..'9': Result := Result * 16 + Ord(S[I]) - Ord('0');
      'A'..'F': Result := Result * 16 + Ord(S[I]) - Ord('A') + 10;
    else
      Fail('bad hex digit in ' + S);
    end;
end;

{ '0041 030A' -> the code points }
function ParseCodePoints(const S: string): TLandrixXmlCodePoints;
var
  I, Start, N: Integer;
begin
  Result := nil;
  N := 0;
  I := 1;
  while I <= Length(S) do
  begin
    while (I <= Length(S)) and (S[I] = ' ') do
      Inc(I);
    Start := I;
    while (I <= Length(S)) and (S[I] <> ' ') do
      Inc(I);
    if I > Start then
    begin
      SetLength(Result, N + 1);
      Result[N] := HexValue(Copy(S, Start, I - Start));
      Inc(N);
    end;
  end;
end;

function HexText(const CodePoints: TLandrixXmlCodePoints): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to Integer(Length(CodePoints)) - 1 do
  begin
    if I > 0 then
      Result := Result + ' ';
    Result := Result + IntToHex(CodePoints[I], 4);
  end;
end;

{ Splits a line source;NFC;NFD;NFKC;NFKD (more fields and a comment
  allowed) into Columns[0..4]; False if it has fewer fields. }
function SplitColumns(const Line: string; var Columns: TColumns): Boolean;
var
  I, K, Start: Integer;
begin
  K := 0;
  Start := 1;
  for I := 1 to Length(Line) + 1 do
    if (K <= 4) and ((I > Length(Line)) or (Line[I] = ';')) then
    begin
      Columns[K] := Copy(Line, Start, I - Start);
      Inc(K);
      Start := I + 1;
    end;
  Result := K = 5;
end;

{ Checks the invariants of NormalizationTest.txt for one line:
  NFC: c2 = NFC(c1) = NFC(c2) = NFC(c3), c4 = NFC(c4) = NFC(c5);
  NFD: c3 = NFD(c1) = NFD(c2) = NFD(c3), c5 = NFD(c4) = NFD(c5);
  NFKC: c4 = NFKC(c1..c5); NFKD: c5 = NFKD(c1..c5); and the UTF-8 form
  gives the same as the code point form. }
procedure CheckLine(const Columns: TColumns; const Where: string);
const
  { per form and source column (0-based): the expected column }
  Expected: array[0..3, 0..4] of Integer = (
    (1, 1, 1, 3, 3),
    (2, 2, 2, 4, 4),
    (3, 3, 3, 3, 3),
    (4, 4, 4, 4, 4));
var
  Points: array[0..4] of TLandrixXmlCodePoints;
  F, K: Integer;
  Actual: TLandrixXmlCodePoints;
  Utf8: TLandrixXmlUtf8;
begin
  for K := 0 to 4 do
    Points[K] := ParseCodePoints(Columns[K]);
  for F := 0 to 3 do
    for K := 0 to 4 do
    begin
      Actual := LandrixXmlNormalizeCodePoints(Points[K], Forms[F]);
      CheckEqualsStr(HexText(Points[Expected[F][K]]), HexText(Actual),
        Where + ': ' + FormNames[F] + ' of column ' + IntToStr(K + 1) + ' (' + Columns[K] + ')');
      Utf8 := LandrixXmlNormalizeUtf8(LandrixXmlCodePointsToUtf8(Points[K], 0, Integer(Length(Points[K]))), Forms[F]);
      CheckEqualsStr(HexText(Points[Expected[F][K]]), HexText(LandrixXmlUtf8ToCodePoints(Utf8)),
        Where + ': UTF-8 ' + FormNames[F] + ' of column ' + IntToStr(K + 1) + ' (' + Columns[K] + ')');
    end;
end;

procedure TestSample;
var
  Columns: TColumns;
  I: Integer;
begin
  for I := 0 to 4 do
    Columns[I] := '';
  for I := 0 to High(Sample) do
  begin
    Check(SplitColumns(Sample[I], Columns), 'sample ' + IntToStr(I));
    CheckLine(Columns, 'sample ' + IntToStr(I));
  end;
end;

function Utf8Of(const Hex: string): TLandrixXmlUtf8;
var
  Points: TLandrixXmlCodePoints;
begin
  Points := ParseCodePoints(Hex);
  Result := LandrixXmlCodePointsToUtf8(Points, 0, Integer(Length(Points)));
end;

{ Already normalized UTF-8 comes back unchanged; malformed UTF-8 raises. }
procedure TestUtf8;
var
  S: TLandrixXmlUtf8;
  Raised: Boolean;
begin
  S := LandrixXmlStringToUtf8('plain ASCII');
  CheckEqualsUtf8(S, LandrixXmlNormalizeUtf8(S, xnfNfkd), 'ASCII');
  S := Utf8Of('00E4 0078');
  CheckEqualsUtf8(S, LandrixXmlNormalizeUtf8(S, xnfNfc), 'NFC of a-umlaut');
  CheckEqualsUtf8(Utf8Of('0061 0308 0078'), LandrixXmlNormalizeUtf8(S, xnfNfd), 'NFD of a-umlaut');
  { a lead byte without its continuation byte }
  S := Copy(S, 1, 1) + Copy(S, 3, 1);
  Raised := False;
  try
    LandrixXmlNormalizeUtf8(S, xnfNfc);
  except
    on E: ELandrixXmlError do
      Raised := E.Code = xecInvalidUnicode;
  end;
  Check(Raised, 'malformed UTF-8');
end;

procedure TestUnicodeSuite;
var
  Lines: TStringList;
  Columns: TColumns;
  Listed: array of Boolean;
  I, F, Cp, Count: Integer;
  Part1: Boolean;
  One, Actual: TLandrixXmlCodePoints;
  Line: string;
begin
  Actual := nil;
  if not FileExists(SuiteFile) then
    Exit;
  for I := 0 to 4 do
    Columns[I] := '';
  Listed := nil;
  One := nil;
  SetLength(Listed, $110000);
  for I := 0 to $10FFFF do
    Listed[I] := False;
  Part1 := False;
  Count := 0;
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(SuiteFile);
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Lines[I];
      if Copy(Line, 1, 5) = '@Part' then
        Part1 := Copy(Line, 1, 6) = '@Part1'
      else if (Line <> '') and (Line[1] <> '#') and SplitColumns(Line, Columns) then
      begin
        CheckLine(Columns, 'line ' + IntToStr(I + 1));
        if Part1 then
          Listed[HexValue(Columns[0])] := True;
        Inc(Count);
      end;
    end;
  finally
    Lines.Free;
  end;
  Check(Count > 19000, 'lines of the suite: ' + IntToStr(Count));
  { every code point not listed in part 1 is invariant }
  SetLength(One, 1);
  for Cp := 0 to $10FFFF do
    if not Listed[Cp] and ((Cp < $D800) or (Cp > $DFFF)) then
    begin
      One[0] := Cp;
      for F := 0 to 3 do
      begin
        Actual := LandrixXmlNormalizeCodePoints(One, Forms[F]);
        if (Integer(Length(Actual)) <> 1) or (Actual[0] <> Cp) then
          Fail(FormNames[F] + ' of ' + IntToHex(Cp, 4) + ' is ' + HexText(Actual));
      end;
    end;
end;

procedure Register;
begin
  RegisterTest('Normalize.Sample', TestSample);
  RegisterTest('Normalize.Utf8', TestUtf8);
  RegisterTest('Normalize.UnicodeSuite', TestUnicodeSuite);
end;

end.
