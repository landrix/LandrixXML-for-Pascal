{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Tests for LandrixXmlEncoding: encoding detection, conversion to UTF-8,
  error handling, opt-in repair, offset mapping and the declaration
  scanner. Expected results for the files in tests/data/encoding come from
  Python's codecs (tools/gen-encoding-testdata.py), an independent oracle. }

unit LandrixXmlTestEncoding;

{$I LandrixXml.inc}

interface

procedure Register;

implementation

uses
  SysUtils,
  Classes,
  LandrixXmlBase,
  LandrixXmlEncoding,
  LandrixXmlTestFramework;

type
  { Memory stream that returns at most 7 bytes per Read, to exercise the
    chunked reading loop. }
  TTrickleStream = class(TMemoryStream)
  public
    function Read(var Buffer; Count: Longint): Longint; override;
  end;

function TTrickleStream.Read(var Buffer; Count: Longint): Longint;
begin
  if Count > 7 then
    Count := 7;
  Result := inherited Read(Buffer, Count);
end;

{ --- helpers ------------------------------------------------------------- }

function DataDir: string;
begin
  Result := RepositoryRoot + 'tests' + PathDelim + 'data' + PathDelim +
    'encoding' + PathDelim;
end;

function ReadFileBytes(const FileName: string): AnsiString;
var
  Stream: TFileStream;
begin
  Result := '';
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, Integer(Stream.Size));
    if Length(Result) > 0 then
      Stream.ReadBuffer(PAnsiChar(Result)^, Length(Result));
  finally
    Stream.Free;
  end;
end;

function ReadFileUtf8(const FileName: string): TLandrixXmlUtf8;
var
  Raw: AnsiString;
begin
  Raw := ReadFileBytes(FileName);
  Result := '';
  SetLength(Result, Length(Raw));
  if Length(Raw) > 0 then
    Move(PAnsiChar(Raw)^, PAnsiChar(Result)^, Length(Raw));
end;

{ Data of the input as TLandrixXmlUtf8 (byte copy, no validation). }
function InputText(Input: TLandrixXmlInput): TLandrixXmlUtf8;
begin
  Result := '';
  SetLength(Result, Input.Size);
  if Input.Size > 0 then
    Move(Input.Data^, PAnsiChar(Result)^, Input.Size);
end;

function A(const S: string): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(S);
end;

{ Byte copy of an AnsiString (no code page conversion). }
function RawUtf8(const S: AnsiString): TLandrixXmlUtf8;
begin
  Result := '';
  SetLength(Result, Length(S));
  if Length(S) > 0 then
    Move(PAnsiChar(S)^, PAnsiChar(Result)^, Length(S));
end;

{ ASCII bytes as native string for messages (no code page conversion). }
function Show(const S: AnsiString): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    Result := Result + Char(Ord(S[I]));
end;

procedure CheckEncoding(Expected, Actual: TLandrixXmlEncoding; const Msg: string);
begin
  CheckEquals(Ord(Expected), Ord(Actual), Msg + ' (encoding '
    + LandrixXmlEncodingName(Expected) + ' expected, got '
    + LandrixXmlEncodingName(Actual) + ')');
end;

procedure CheckErrorCode(Expected, Actual: TLandrixXmlErrorCode; const Msg: string);
begin
  CheckEquals(Ord(Expected), Ord(Actual), Msg + ' (error code)');
end;

procedure LoadBytes(Input: TLandrixXmlInput; const Bytes: AnsiString);
begin
  Input.LoadFromBuffer(PAnsiChar(Bytes)^, Length(Bytes));
end;

{ UTF-16 code units as bytes. }
function Utf16(BigEndian: Boolean; const Units: array of Word): AnsiString;
var
  I: Integer;
begin
  Result := '';
  SetLength(Result, 2 * Length(Units));
  for I := 0 to Integer(High(Units)) do
    if BigEndian then
    begin
      Result[2 * I + 1] := AnsiChar(Units[I] shr 8);
      Result[2 * I + 2] := AnsiChar(Units[I] and $FF);
    end
    else
    begin
      Result[2 * I + 1] := AnsiChar(Units[I] and $FF);
      Result[2 * I + 2] := AnsiChar(Units[I] shr 8);
    end;
end;

{ ASCII text widened to UTF-16. }
function Utf16Ascii(BigEndian: Boolean; const S: AnsiString): AnsiString;
var
  I: Integer;
  Units: array of Word;
begin
  Units := nil;
  SetLength(Units, Length(S));
  for I := 1 to Length(S) do
    Units[I - 1] := Ord(S[I]);
  Result := Utf16(BigEndian, Units);
end;

procedure ExpectError(const Bytes: AnsiString; Code: TLandrixXmlErrorCode;
  Offset: Int64; const Name: string);
var
  Input: TLandrixXmlInput;
begin
  Input := TLandrixXmlInput.Create;
  try
    try
      LoadBytes(Input, Bytes);
      FailNotRaised('ELandrixXmlError for ' + Name);
    except
      on E: ELandrixXmlError do
      begin
        CheckErrorCode(Code, E.Code, Name);
        if Offset >= -1 then
          CheckEqualsInt64(Offset, E.Offset, Name + ': offset');
      end;
    end;
    CheckEquals(0, Input.Size, Name + ': failed load leaves the input empty');
  finally
    Input.Free;
  end;
end;

{ --- file cases ------------------------------------------------------------ }

procedure CheckFileCase(const Name: string; Encoding: TLandrixXmlEncoding;
  HadBom: Boolean; const Declared: string);
var
  Input: TLandrixXmlInput;
  Expected: TLandrixXmlUtf8;
  Raw: AnsiString;
  Stream: TMemoryStream;
  Trickle: TTrickleStream;
  Way: Integer;
begin
  Expected := ReadFileUtf8(DataDir + Name + '.utf8');
  Raw := ReadFileBytes(DataDir + Name + '.xml');
  Input := TLandrixXmlInput.Create;
  Stream := TMemoryStream.Create;
  Trickle := TTrickleStream.Create;
  try
    Stream.WriteBuffer(PAnsiChar(Raw)^, Length(Raw));
    Trickle.WriteBuffer(PAnsiChar(Raw)^, Length(Raw));
    for Way := 1 to 4 do
    begin
      case Way of
        1: Input.LoadFromFile(DataDir + Name + '.xml');
        2:
          begin
            Stream.Position := 0;
            Input.LoadFromStream(Stream);
          end;
        3: LoadBytes(Input, Raw);
        4:
          begin
            Trickle.Position := 0;
            Input.LoadFromStream(Trickle);
          end;
      end;
      CheckEqualsUtf8(Expected, InputText(Input), Name + ' way ' + IntToStr(Way) + ': content');
      CheckEncoding(Encoding, Input.SourceEncoding, Name + ' way ' + IntToStr(Way));
      Check(Input.HadBom = HadBom, Name + ': HadBom');
      CheckEqualsUtf8(A(Declared), Input.DeclaredEncoding, Name + ': DeclaredEncoding');
      CheckEqualsInt64(Length(Raw), Input.OriginalSize, Name + ': OriginalSize');
      CheckEquals(0, Ord(Input.Data[Input.Size]), Name + ': sentinel');
      CheckEqualsInt64(Length(Raw), Input.OriginalOffset(Input.Size), Name + ': EOF maps to original size');
    end;
  finally
    Trickle.Free;
    Stream.Free;
    Input.Free;
  end;
end;

procedure TestFiles;
begin
  CheckFileCase('utf8', xenUtf8, False, 'UTF-8');
  CheckFileCase('utf8-bom', xenUtf8, True, 'UTF-8');
  CheckFileCase('utf8-nodecl', xenUtf8, False, '');
  CheckFileCase('utf8-bom-nodecl', xenUtf8, True, '');
  CheckFileCase('utf8-lowercase', xenUtf8, False, 'utf-8');
  CheckFileCase('utf16le-bom', xenUtf16LE, True, 'UTF-16');
  CheckFileCase('utf16be-bom', xenUtf16BE, True, 'UTF-16');
  CheckFileCase('utf16le-bom-nodecl', xenUtf16LE, True, '');
  CheckFileCase('utf16le-bom-le-decl', xenUtf16LE, True, 'UTF-16LE');
  CheckFileCase('utf16le-nobom', xenUtf16LE, False, 'UTF-16LE');
  CheckFileCase('utf16be-nobom', xenUtf16BE, False, 'UTF-16BE');
  CheckFileCase('iso-8859-1', xenIso88591, False, 'ISO-8859-1');
  CheckFileCase('latin1-alias', xenIso88591, False, 'latin1');
  CheckFileCase('windows-1252', xenWindows1252, False, 'windows-1252');
  CheckFileCase('cp1252-alias', xenWindows1252, False, 'CP1252');
  CheckFileCase('iso-8859-15', xenIso885915, False, 'ISO-8859-15');
  CheckFileCase('latin9-alias', xenIso885915, False, 'Latin-9');
  CheckFileCase('ascii', xenAscii, False, 'US-ASCII');
end;

procedure TestFullTables;
begin
  { all bytes $80-$FF against Python's codecs }
  CheckFileCase('iso-8859-1-all', xenIso88591, False, 'ISO-8859-1');
  CheckFileCase('windows-1252-all', xenWindows1252, False, 'windows-1252');
  CheckFileCase('iso-8859-15-all', xenIso885915, False, 'ISO-8859-15');
  CheckFileCase('latin1-with-0x80', xenIso88591, False, 'ISO-8859-1');
end;

{ --- errors ----------------------------------------------------------------- }

procedure TestBomDeclarationMismatch;
begin
  ExpectError(Bytes([$EF, $BB, $BF]) + '<?xml version="1.0" encoding="ISO-8859-1"?><r/>',
    xecEncoding, 33, 'UTF-8 BOM + ISO-8859-1');
  ExpectError(Bytes([$EF, $BB, $BF]) + '<?xml version="1.0" encoding="UTF-16"?><r/>',
    xecEncoding, 33, 'UTF-8 BOM + UTF-16');
  ExpectError(Bytes([$FF, $FE]) + Utf16Ascii(False, '<?xml version="1.0" encoding="UTF-8"?><r/>'),
    xecEncoding, 62, 'UTF-16LE BOM + UTF-8');
  ExpectError(Bytes([$FF, $FE]) + Utf16Ascii(False, '<?xml version="1.0" encoding="UTF-16BE"?><r/>'),
    xecEncoding, 62, 'UTF-16LE BOM + UTF-16BE');
  ExpectError(Bytes([$FE, $FF]) + Utf16Ascii(True, '<?xml version="1.0" encoding="ISO-8859-1"?><r/>'),
    xecEncoding, 62, 'UTF-16BE BOM + ISO-8859-1');
  ExpectError('<?xml version="1.0" encoding="UTF-16"?><r/>',
    xecEncoding, 30, '8-bit input declaring UTF-16');
end;

procedure TestUtf16WithoutBom;
begin
  ExpectError(Utf16Ascii(False, '<?xml version="1.0" encoding="UTF-16"?><r/>'),
    xecEncoding, 60, 'UTF-16 declared without BOM');
  ExpectError(Utf16Ascii(False, '<?xml version="1.0"?><r/>'),
    xecEncoding, 0, 'UTF-16 without BOM and without encoding');
  ExpectError(Utf16Ascii(False, '<?xml version="1.0" encoding="UTF-16BE"?><r/>'),
    xecEncoding, 60, 'LE data declared UTF-16BE');
  ExpectError(Utf16Ascii(True, '<?xml version="1.0" encoding="UTF-16LE"?><r/>'),
    xecEncoding, 60, 'BE data declared UTF-16LE');
  ExpectError(Utf16Ascii(True, '<?xml version="1.0" encoding="UTF-8"?><r/>'),
    xecEncoding, 60, 'BE data declared UTF-8');
  ExpectError(Utf16Ascii(False, '<r/>'), xecEncoding, 0, 'UTF-16LE without BOM and without declaration');
  ExpectError(Utf16Ascii(True, '<r/>'), xecEncoding, 0, 'UTF-16BE without BOM and without declaration');
end;

procedure TestErrorLineColumn;
var
  Input: TLandrixXmlInput;
begin
  Input := TLandrixXmlInput.Create;
  try
    try
      LoadBytes(Input, '<?xml version="1.0" encoding="ISO-8859-1"?>' + Bytes([13, 10]) + 'abc' + Bytes([$E4, 0]));
      FailNotRaised('ELandrixXmlError for NUL in ISO-8859-1');
    except
      on E: ELandrixXmlError do
      begin
        CheckEquals(2, E.Line, 'ISO-8859-1 NUL: line');
        CheckEquals(5, E.Column, 'ISO-8859-1 NUL: column');
        CheckEqualsInt64(49, E.Offset, 'ISO-8859-1 NUL: offset');
      end;
    end;
    try
      LoadBytes(Input, Bytes([$FF, $FE]) + Utf16(False, [$3C, $72, $3E, 13, $41, 10, $E4, $DC00]));
      FailNotRaised('ELandrixXmlError for lone surrogate');
    except
      on E: ELandrixXmlError do
      begin
        CheckEquals(3, E.Line, 'UTF-16 surrogate: line (CR and LF)');
        CheckEquals(2, E.Column, 'UTF-16 surrogate: column');
        CheckEqualsInt64(16, E.Offset, 'UTF-16 surrogate: offset');
      end;
    end;
  finally
    Input.Free;
  end;
end;

procedure TestLoadVariants;
var
  Input: TLandrixXmlInput;
  Stream: TMemoryStream;
  Raw: AnsiString;
begin
  Input := TLandrixXmlInput.Create;
  Stream := TMemoryStream.Create;
  try
    { stream read from the current position }
    Raw := 'garbage<r/>';
    Stream.WriteBuffer(PAnsiChar(Raw)^, Length(Raw));
    Stream.Position := 7;
    Input.LoadFromStream(Stream);
    CheckEqualsUtf8(A('<r/>'), InputText(Input), 'stream from position 7');
    CheckEqualsInt64(4, Input.OriginalSize, 'OriginalSize counts from the position');

    { UTF-16 BOM only }
    LoadBytes(Input, Bytes([$FF, $FE]));
    CheckEquals(0, Input.Size, 'UTF-16 BOM only');
    Check(Input.HadBom, 'UTF-16 BOM only: HadBom');
    CheckEncoding(xenUtf16LE, Input.SourceEncoding, 'UTF-16 BOM only');

    { a file that cannot be opened clears the old content }
    LoadBytes(Input, '<r/>');
    try
      Input.LoadFromFile(DataDir + 'does-not-exist.xml');
      FailNotRaised('exception for a missing file');
    except
      on E: Exception do ;
    end;
    CheckEquals(0, Input.Size, 'missing file leaves the input empty');
  finally
    Stream.Free;
    Input.Free;
  end;
end;

procedure TestUnsupportedSignatures;
begin
  ExpectError(Bytes([$00, $00, $FE, $FF, $00, $00, $00, $3C]), xecEncoding, 0, 'UTF-32BE BOM');
  ExpectError(Bytes([$FF, $FE, $00, $00, $3C, $00, $00, $00]), xecEncoding, 0, 'UTF-32LE BOM');
  ExpectError(Bytes([$3C, $00, $00, $00, $3F, $00, $00, $00]), xecEncoding, 0, 'UTF-32LE without BOM');
  ExpectError(Bytes([$00, $00, $00, $3C, $00, $00, $00, $3F]), xecEncoding, 0, 'UTF-32BE without BOM');
  ExpectError(Bytes([$4C, $6F, $A7, $94, $93, $40]), xecEncoding, 0, 'EBCDIC');
end;

procedure TestUnknownEncoding;
var
  Input: TLandrixXmlInput;
begin
  Input := TLandrixXmlInput.Create;
  try
    try
      LoadBytes(Input, '<?xml version="1.0" encoding="KOI8-R"?><r/>');
      FailNotRaised('ELandrixXmlError for KOI8-R');
    except
      on E: ELandrixXmlError do
      begin
        CheckErrorCode(xecEncoding, E.Code, 'KOI8-R');
        Check(Pos('KOI8-R', E.Message) > 0, 'message names the encoding: ' + E.Message);
        CheckEqualsInt64(30, E.Offset, 'KOI8-R: offset of the encoding name');
        CheckEquals(1, E.Line, 'KOI8-R: line');
        CheckEquals(31, E.Column, 'KOI8-R: column');
      end;
    end;
  finally
    Input.Free;
  end;
  ExpectError('<?xml version="1.0" encoding="UTF-32"?><r/>', xecEncoding, 30, 'declared UTF-32');
  ExpectError('<?xml version="1.0" encoding="ISO-8859-2"?><r/>', xecEncoding, 30, 'ISO-8859-2');
end;

procedure TestInvalidUtf8;
var
  Input: TLandrixXmlInput;
  Head: AnsiString;
begin
  Head := '<?xml version="1.0"?>' + Bytes([13, 10]) + '<r>';
  ExpectError(Head + Bytes([$FF]) + '</r>', xecInvalidUnicode, Length(Head), 'invalid byte');
  ExpectError(Bytes([$EF, $BB, $BF]) + Head + Bytes([$C3, $28]), xecInvalidUnicode,
    3 + Int64(Length(Head)), 'invalid byte after BOM');
  ExpectError(Bytes([$EF, $BB, $3C, $72, $2F, $3E]), xecInvalidUnicode, 0, 'truncated BOM');
  ExpectError('<?xml version="1.0" encoding="UTF-8"?><r>' + Bytes([$E4]) + '</r>',
    xecInvalidUnicode, 41, 'Windows-1252 umlaut in UTF-8 document');

  Input := TLandrixXmlInput.Create;
  try
    try
      LoadBytes(Input, Head + 'ab' + Bytes([$C3, $A4]) + 'c' + Bytes([$80]));
      FailNotRaised('ELandrixXmlError for line/column');
    except
      on E: ELandrixXmlError do
      begin
        CheckEquals(2, E.Line, 'line (CR LF counts once)');
        CheckEquals(8, E.Column, 'column in characters');
      end;
    end;
  finally
    Input.Free;
  end;
end;

procedure TestAscii;
begin
  ExpectError('<?xml version="1.0" encoding="US-ASCII"?><r>' + Bytes([$C3, $A4]) + '</r>',
    xecEncoding, 44, 'byte >= $80 in US-ASCII');
end;

procedure TestNul;
begin
  ExpectError('<r>' + Bytes([0]) + '</r>', xecInvalidChar, 3, 'NUL in UTF-8');
  ExpectError(Bytes([$EF, $BB, $BF]) + '<r>' + Bytes([0]), xecInvalidChar, 6, 'NUL in UTF-8 after BOM');
  ExpectError('<?xml version="1.0" encoding="ISO-8859-1"?><r>' + Bytes([0]), xecInvalidChar, 46, 'NUL in ISO-8859-1');
  ExpectError(Bytes([$FF, $FE]) + Utf16(False, [$3C, $72, $3E, $0, $3C]), xecInvalidChar, 8, 'NUL in UTF-16LE');
end;

procedure TestUtf16Errors;
begin
  ExpectError(Bytes([$FF, $FE]) + Utf16Ascii(False, '<r/>') + Bytes([$3E]), xecEncoding, 10, 'odd byte count');
  ExpectError(Bytes([$FF, $FE]) + Utf16(False, [$3C, $72, $3E, $D83D, $3C]), xecInvalidUnicode, 8, 'lone high surrogate');
  ExpectError(Bytes([$FE, $FF]) + Utf16(True, [$3C, $72, $3E, $DE00]), xecInvalidUnicode, 8, 'lone low surrogate (BE)');
  ExpectError(Bytes([$FF, $FE]) + Utf16(False, [$3C, $D83D]), xecInvalidUnicode, 4, 'high surrogate at end');
end;

procedure TestMalformedDeclarationInInput;
begin
  ExpectError('<?xml version="2.0"?><r/>', xecSyntax, 15, 'version 2.0');
  ExpectError(Bytes([$EF, $BB, $BF]) + '<?xml version="1.0" encoding=""?><r/>', xecSyntax, 33, 'empty encoding after BOM');
  ExpectError(Bytes([$FF, $FE]) + Utf16Ascii(False, '<?xml version=1.0?><r/>'), xecSyntax, 2 + 2 * 14, 'unquoted version in UTF-16');
end;

{ --- empty input, state, options ------------------------------------------- }

procedure TestEmptyAndState;
var
  Input: TLandrixXmlInput;
begin
  Input := TLandrixXmlInput.Create;
  try
    Check(Input.Data <> nil, 'Data never nil');
    CheckEquals(0, Ord(Input.Data[0]), 'sentinel of a new input');
    LoadBytes(Input, '');
    CheckEquals(0, Input.Size, 'empty input');
    Check(Input.Data <> nil, 'Data never nil after empty load');
    LoadBytes(Input, Bytes([$EF, $BB, $BF]));
    CheckEquals(0, Input.Size, 'BOM only');
    Check(Input.HadBom, 'BOM only: HadBom');
    CheckEncoding(xenUtf8, Input.SourceEncoding, 'BOM only');

    LoadBytes(Input, '<r/>');
    CheckEquals(4, Input.Size, 'loaded');
    try
      LoadBytes(Input, '<r>' + Bytes([$FF]));
    except
      on E: ELandrixXmlError do ;
    end;
    CheckEquals(0, Input.Size, 'failed load leaves the input empty');
    CheckEncoding(xenUnknown, Input.SourceEncoding, 'failed load resets SourceEncoding');
    CheckEquals(0, Ord(Input.Data[0]), 'sentinel after failed load');

    { reload from the input's own memory }
    LoadBytes(Input, '<?xml version="1.0"?><r/>');
    Input.LoadFromBuffer(Input.Data^, Input.Size);
    CheckEqualsUtf8(A('<?xml version="1.0"?><r/>'), InputText(Input), 'reload from own Data');
  finally
    Input.Free;
  end;
end;

procedure TestFallbackEncoding;
var
  Input: TLandrixXmlInput;
  Raw: AnsiString;
  Expected: TLandrixXmlUtf8;
begin
  Raw := ReadFileBytes(DataDir + 'utf8-declared-cp1252.xml');
  Expected := ReadFileUtf8(DataDir + 'utf8-declared-cp1252.utf8');
  ExpectError(Raw, xecInvalidUnicode, 42, 'strict by default');
  Input := TLandrixXmlInput.Create;
  try
    try
      Input.FallbackEncoding := xenUtf8;
      FailNotRaised('ELandrixXmlError for FallbackEncoding = UTF-8');
    except
      on E: ELandrixXmlError do
        CheckErrorCode(xecInvalidArgument, E.Code, 'FallbackEncoding = UTF-8');
    end;
    try
      Input.FallbackEncoding := xenUtf16LE;
      FailNotRaised('ELandrixXmlError for FallbackEncoding = UTF-16LE');
    except
      on E: ELandrixXmlError do
        CheckErrorCode(xecInvalidArgument, E.Code, 'FallbackEncoding = UTF-16LE');
    end;
    CheckEncoding(xenUnknown, Input.FallbackEncoding, 'rejected value not stored');

    Input.FallbackEncoding := xenWindows1252;
    LoadBytes(Input, Raw);
    CheckEqualsUtf8(Expected, InputText(Input), 'fallback result');
    CheckEncoding(xenWindows1252, Input.SourceEncoding, 'SourceEncoding reports the fallback');
    CheckEqualsUtf8(A('UTF-8'), Input.DeclaredEncoding, 'DeclaredEncoding as written');

    { valid UTF-8 stays UTF-8 }
    LoadBytes(Input, '<r>' + Bytes([$C3, $A4]) + '</r>');
    CheckEncoding(xenUtf8, Input.SourceEncoding, 'valid UTF-8 ignores the fallback');
    CheckEqualsUtf8(Utf8Bytes([$3C, $72, $3E, $C3, $A4, $3C, $2F, $72, $3E]), InputText(Input), 'valid UTF-8 unchanged');

    { never with a BOM }
    try
      LoadBytes(Input, Bytes([$EF, $BB, $BF]) + '<r>' + Bytes([$E4]) + '</r>');
      FailNotRaised('ELandrixXmlError: fallback must not apply with a BOM');
    except
      on E: ELandrixXmlError do
        CheckErrorCode(xecInvalidUnicode, E.Code, 'fallback with BOM');
    end;

    { never for UTF-16 errors }
    try
      LoadBytes(Input, Bytes([$FF, $FE]) + Utf16(False, [$3C, $D83D]));
      FailNotRaised('ELandrixXmlError: fallback must not apply to UTF-16');
    except
      on E: ELandrixXmlError do
        CheckErrorCode(xecInvalidUnicode, E.Code, 'fallback with UTF-16');
    end;

    { NUL is still rejected in the fallback path }
    try
      LoadBytes(Input, '<r>' + Bytes([$E4, 0]) + '</r>');
      FailNotRaised('ELandrixXmlError: NUL in fallback path');
    except
      on E: ELandrixXmlError do
      begin
        CheckErrorCode(xecInvalidChar, E.Code, 'NUL in fallback path');
        CheckEqualsInt64(4, E.Offset, 'NUL in fallback path: offset');
      end;
    end;
  finally
    Input.Free;
  end;
end;

procedure TestLatin1AsWindows1252;
var
  Input: TLandrixXmlInput;
  Head: AnsiString;
begin
  Head := '<?xml version="1.0" encoding="ISO-8859-1"?><r>';
  Input := TLandrixXmlInput.Create;
  try
    LoadBytes(Input, Head + Bytes([$80]));
    CheckEqualsUtf8(RawUtf8(Head) + Utf8Bytes([$C2, $80]), InputText(Input), 'strict: 0x80 is U+0080');
    CheckEncoding(xenIso88591, Input.SourceEncoding, 'strict');
    Input.Latin1AsWindows1252 := True;
    LoadBytes(Input, Head + Bytes([$80]));
    CheckEqualsUtf8(RawUtf8(Head) + Utf8Bytes([$E2, $82, $AC]), InputText(Input), 'option: 0x80 is the euro sign');
    CheckEncoding(xenWindows1252, Input.SourceEncoding, 'option reports Windows-1252');
    CheckEqualsUtf8(A('ISO-8859-1'), Input.DeclaredEncoding, 'option keeps the declaration');
  finally
    Input.Free;
  end;
end;

procedure TestLoadFromUtf8;
var
  Input: TLandrixXmlInput;
  S: TLandrixXmlUtf8;
begin
  Input := TLandrixXmlInput.Create;
  try
    S := A('<?xml version="1.0" encoding="ISO-8859-1"?><r>') + Utf8Bytes([$C3, $A4]) + A('</r>');
    Input.LoadFromUtf8(S);
    CheckEqualsUtf8(S, InputText(Input), 'string taken as UTF-8');
    CheckEncoding(xenUtf8, Input.SourceEncoding, 'SourceEncoding');
    CheckEqualsUtf8(A('ISO-8859-1'), Input.DeclaredEncoding, 'declaration only recorded');

    Input.LoadFromUtf8(Utf8Bytes([$EF, $BB, $BF, $3C, $72, $2F, $3E]));
    CheckEqualsUtf8(A('<r/>'), InputText(Input), 'BOM removed');
    Check(Input.HadBom, 'HadBom');
    CheckEqualsInt64(3, Input.OriginalOffset(0), 'offset includes the BOM');

    Input.LoadFromUtf8(A('<?xml version="1.0" encoding="KOI8-R"?><r/>'));
    CheckEqualsUtf8(A('KOI8-R'), Input.DeclaredEncoding, 'unsupported name only recorded');

    try
      Input.LoadFromUtf8(Utf8Bytes([$3C, $FF]));
      FailNotRaised('ELandrixXmlError for invalid UTF-8 string');
    except
      on E: ELandrixXmlError do
        CheckErrorCode(xecInvalidUnicode, E.Code, 'invalid UTF-8 string');
    end;
    CheckEquals(0, Input.Size, 'failed LoadFromUtf8 leaves the input empty');
  finally
    Input.Free;
  end;
end;

{ --- offsets ------------------------------------------------------------------ }

procedure TestOriginalOffset;
var
  Input: TLandrixXmlInput;
begin
  Input := TLandrixXmlInput.Create;
  try
    LoadBytes(Input, Bytes([$EF, $BB, $BF]) + '<r>' + Bytes([$C3, $A4]) + '</r>');
    CheckEqualsInt64(3, Input.OriginalOffset(0), 'UTF-8 BOM: start');
    CheckEqualsInt64(8, Input.OriginalOffset(5), 'UTF-8 BOM: after umlaut');
    CheckEqualsInt64(-1, Input.OriginalOffset(-1), 'negative');
    CheckEqualsInt64(Input.OriginalSize, Input.OriginalOffset(MaxInt), 'clamped');

    LoadBytes(Input, '<?xml version="1.0" encoding="windows-1252"?><r>' + Bytes([$E4, $80]) + 'x');
    { converted: umlaut = 2 bytes, euro = 3 bytes, each 1 original byte }
    CheckEqualsInt64(48, Input.OriginalOffset(48), 'single-byte: before umlaut');
    CheckEqualsInt64(49, Input.OriginalOffset(50), 'single-byte: after umlaut');
    CheckEqualsInt64(50, Input.OriginalOffset(53), 'single-byte: after euro');
    CheckEqualsInt64(51, Input.OriginalOffset(54), 'single-byte: EOF');

    LoadBytes(Input, Bytes([$FF, $FE]) + Utf16(False, [$3C, $E4, $D83D, $DE00, $3E]));
    { UTF-8: '<' 1, umlaut 2, emoji 4, '>' 1 }
    CheckEqualsInt64(2, Input.OriginalOffset(0), 'UTF-16: start after BOM');
    CheckEqualsInt64(4, Input.OriginalOffset(1), 'UTF-16: after <');
    CheckEqualsInt64(6, Input.OriginalOffset(3), 'UTF-16: after umlaut');
    CheckEqualsInt64(10, Input.OriginalOffset(7), 'UTF-16: after emoji (surrogate pair)');
    CheckEqualsInt64(12, Input.OriginalOffset(8), 'UTF-16: EOF');
  finally
    Input.Free;
  end;
end;

{ --- declaration scanner ------------------------------------------------------ }

function SpanText(const S: AnsiString; Start, Len: Integer): AnsiString;
begin
  Result := Copy(S, Start + 1, Len);
end;

procedure ScanOk(const S: AnsiString; const Version, Encoding, Standalone: AnsiString;
  EndOffset: Integer);
var
  Decl: TLandrixXmlDeclaration;
  Err: Integer;
begin
  Check(LandrixXmlScanDeclaration(PAnsiChar(S), Length(S), Decl, Err), 'well-formed: ' + Show(S));
  Check(Decl.Present, 'present: ' + Show(S));
  CheckEqualsBytes(Version, SpanText(S, Decl.VersionStart, Decl.VersionLength), 'version of ' + Show(S));
  CheckEqualsBytes(Encoding, SpanText(S, Decl.EncodingStart, Decl.EncodingLength), 'encoding of ' + Show(S));
  CheckEqualsBytes(Standalone, SpanText(S, Decl.StandaloneStart, Decl.StandaloneLength), 'standalone of ' + Show(S));
  CheckEquals(EndOffset, Decl.EndOffset, 'end offset of ' + Show(S));
end;

procedure ScanAbsent(const S: AnsiString);
var
  Decl: TLandrixXmlDeclaration;
  Err: Integer;
begin
  Check(LandrixXmlScanDeclaration(PAnsiChar(S), Length(S), Decl, Err), 'no error: ' + Show(S));
  Check(not Decl.Present, 'not a declaration: ' + Show(S));
end;

procedure ScanFail(const S: AnsiString; ErrorOffset: Integer);
var
  Decl: TLandrixXmlDeclaration;
  Err: Integer;
begin
  Check(not LandrixXmlScanDeclaration(PAnsiChar(S), Length(S), Decl, Err), 'malformed: ' + Show(S));
  CheckEquals(ErrorOffset, Err, 'error offset of ' + Show(S));
end;

procedure TestScanDeclaration;
begin
  ScanOk('<?xml version="1.0"?>', '1.0', '', '', 21);
  ScanOk('<?xml version="1.0"?><r/>', '1.0', '', '', 21);
  ScanOk('<?xml version=''1.0'' encoding=''UTF-8'' standalone=''yes''?>', '1.0', 'UTF-8', 'yes', 55);
  ScanOk('<?xml  version = "1.0"  encoding = "x-y_z.1" ?>', '1.0', 'x-y_z.1', '', 47);
  ScanOk('<?xml version="1.0" standalone="no"?>', '1.0', '', 'no', 37);
  ScanOk('<?xml' + #9 + 'version="1.10"' + #10 + '?>', '1.10', '', '', 23);

  ScanAbsent('');
  ScanAbsent('<r/>');
  ScanAbsent('<?xml-stylesheet href="a.xsl"?>');
  ScanAbsent('<?xmlfoo?>');
  ScanAbsent('<!-- c -->');
  ScanAbsent(' <?xml version="1.0"?>');
  ScanAbsent('<?xm');

  ScanFail('<?xml', 5);
  ScanFail('<?xml?>', 5);
  ScanFail('<?xml ?>', 6);
  ScanFail('<?xml version="1.0"', 19);
  ScanFail('<?xml version="1.0"encoding="UTF-8"?>', 19);
  ScanFail('<?xml encoding="UTF-8" version="1.0"?>', 6);
  ScanFail('<?xml version="1.0" standalone="yes" encoding="UTF-8"?>', 37);
  ScanFail('<?xml version="2.0"?>', 15);
  ScanFail('<?xml version="1."?>', 15);
  ScanFail('<?xml version="1.x"?>', 17);
  ScanFail('<?xml version="1.0', 14);
  ScanFail('<?xml version="1.0''?>', 14);
  ScanFail('<?xml version="1.0" encoding="1abc"?>', 30);
  ScanFail('<?xml version="1.0" encoding=""?>', 30);
  ScanFail('<?xml version="1.0" encoding="UT F"?>', 32);
  ScanFail('<?xml version="1.0" standalone="maybe"?>', 32);
  ScanFail('<?xml version="1.0" ?', 20);
  ScanFail('<?xml version="1.0" foo="bar"?>', 20);
  ScanFail('<?xml version "1.0"?>', 14);
  ScanFail('<?xml version=1.0?>', 14);
  ScanFail('<?xml VERSION="1.0"?>', 6);
  ScanFail('<?xml version="1.0" version="1.0"?>', 20);
end;

procedure TestNamesAndOrdinals;
begin
  CheckEqualsStr('UTF-8', LandrixXmlEncodingName(xenUtf8), 'name UTF-8');
  CheckEqualsStr('UTF-16LE', LandrixXmlEncodingName(xenUtf16LE), 'name UTF-16LE');
  CheckEqualsStr('windows-1252', LandrixXmlEncodingName(xenWindows1252), 'name windows-1252');
  CheckEqualsStr('unknown', LandrixXmlEncodingName(xenUnknown), 'name unknown');
  { append-only enum }
  CheckEquals(0, Ord(xenUnknown), 'xenUnknown');
  CheckEquals(1, Ord(xenUtf8), 'xenUtf8');
  CheckEquals(2, Ord(xenUtf16LE), 'xenUtf16LE');
  CheckEquals(3, Ord(xenUtf16BE), 'xenUtf16BE');
  CheckEquals(4, Ord(xenIso88591), 'xenIso88591');
  CheckEquals(5, Ord(xenWindows1252), 'xenWindows1252');
  CheckEquals(6, Ord(xenAscii), 'xenAscii');
  CheckEquals(7, Ord(xenIso885915), 'xenIso885915');
end;

procedure TestLargeConversion;
var
  Input: TLandrixXmlInput;
  Raw: AnsiString;
  I: Integer;
begin
  { 4 MB of Windows-1252 text with umlauts and euro signs }
  Raw := '<?xml version="1.0" encoding="windows-1252"?><r>';
  I := Length(Raw);
  SetLength(Raw, I + 4 * 1024 * 1024);
  while I < Length(Raw) do
  begin
    Inc(I);
    case I mod 4 of
      0: Raw[I] := AnsiChar($E4);
      1: Raw[I] := AnsiChar($80);
      2: Raw[I] := 'a';
    else
      Raw[I] := AnsiChar(10);
    end;
  end;
  Input := TLandrixXmlInput.Create;
  try
    LoadBytes(Input, Raw);
    CheckEquals(48 + 1024 * 1024 * (2 + 3 + 1 + 1), Input.Size, 'converted size');
    CheckEqualsInt64(Length(Raw), Input.OriginalOffset(Input.Size), 'EOF offset');
  finally
    Input.Free;
  end;
end;

procedure Register;
begin
  RegisterTest('Encoding.Files', TestFiles);
  RegisterTest('Encoding.FullTables', TestFullTables);
  RegisterTest('Encoding.BomDeclarationMismatch', TestBomDeclarationMismatch);
  RegisterTest('Encoding.Utf16WithoutBom', TestUtf16WithoutBom);
  RegisterTest('Encoding.UnsupportedSignatures', TestUnsupportedSignatures);
  RegisterTest('Encoding.UnknownEncoding', TestUnknownEncoding);
  RegisterTest('Encoding.InvalidUtf8', TestInvalidUtf8);
  RegisterTest('Encoding.Ascii', TestAscii);
  RegisterTest('Encoding.Nul', TestNul);
  RegisterTest('Encoding.ErrorLineColumn', TestErrorLineColumn);
  RegisterTest('Encoding.LoadVariants', TestLoadVariants);
  RegisterTest('Encoding.Utf16Errors', TestUtf16Errors);
  RegisterTest('Encoding.MalformedDeclarationInInput', TestMalformedDeclarationInInput);
  RegisterTest('Encoding.EmptyAndState', TestEmptyAndState);
  RegisterTest('Encoding.FallbackEncoding', TestFallbackEncoding);
  RegisterTest('Encoding.Latin1AsWindows1252', TestLatin1AsWindows1252);
  RegisterTest('Encoding.LoadFromUtf8', TestLoadFromUtf8);
  RegisterTest('Encoding.OriginalOffset', TestOriginalOffset);
  RegisterTest('Encoding.ScanDeclaration', TestScanDeclaration);
  RegisterTest('Encoding.NamesAndOrdinals', TestNamesAndOrdinals);
  RegisterTest('Encoding.LargeConversion', TestLargeConversion);
end;

end.
