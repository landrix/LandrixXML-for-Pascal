{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Tests for LandrixXmlBase: UTF-8/UTF-16 coding, conversions, exception,
  diagnostics and the byte buffer. }

unit LandrixXmlTestBase;

{$I LandrixXml.inc}

interface

procedure Register;

implementation

uses
  SysUtils,
  Classes,
  LandrixXmlBase,
  LandrixXmlTestFramework;

{ --- helpers ------------------------------------------------------------ }

function EncodeCp(CodePoint: Cardinal): TLandrixXmlUtf8;
var
  Buf: array[0..3] of AnsiChar;
  N, I: Integer;
begin
  N := LandrixXmlEncodeUtf8(CodePoint, @Buf[0]);
  Result := '';
  SetLength(Result, N);
  for I := 0 to N - 1 do
    Result[I + 1] := Buf[I];
end;

procedure CheckErrorCode(Expected, Actual: TLandrixXmlErrorCode; const Msg: string);
begin
  CheckEquals(Ord(Expected), Ord(Actual), Msg + ' (error code)');
end;

procedure CheckMalformedUtf8(const S: TLandrixXmlUtf8; ExpectedBad: Integer;
  const Name: string);
var
  Bad: Integer;
  CodePoint: Cardinal;
begin
  Check(not LandrixXmlValidateUtf8(S, Bad), Name + ': must be invalid');
  CheckEquals(ExpectedBad, Bad, Name + ': bad offset');
  try
    LandrixXmlUtf8ToWide(S);
    FailNotRaised('ELandrixXmlError for ' + Name);
  except
    on E: ELandrixXmlError do
    begin
      CheckErrorCode(xecInvalidUnicode, E.Code, Name);
      CheckEqualsInt64(ExpectedBad, E.Offset, Name + ': exception offset');
    end;
  end;
  if ExpectedBad = 0 then
    CheckEquals(0, LandrixXmlDecodeUtf8(PAnsiChar(S), Length(S), CodePoint),
      Name + ': DecodeUtf8 must return 0');
end;

procedure CheckInvalidUtf16(const S: TLandrixXmlWide; ExpectedBad: Integer;
  const Name: string);
begin
  try
    LandrixXmlWideToUtf8(S);
    FailNotRaised('ELandrixXmlError for ' + Name);
  except
    on E: ELandrixXmlError do
    begin
      CheckErrorCode(xecInvalidUnicode, E.Code, Name);
      CheckEqualsInt64(ExpectedBad, E.Offset, Name + ': exception offset');
    end;
  end;
end;

{ --- code point primitives ---------------------------------------------- }

procedure TestEncodeBoundaries;
begin
  CheckEqualsUtf8(Utf8Bytes([$00]), EncodeCp($0), 'U+0000');
  CheckEqualsUtf8(Utf8Bytes([$41]), EncodeCp($41), 'U+0041');
  CheckEqualsUtf8(Utf8Bytes([$7F]), EncodeCp($7F), 'U+007F');
  CheckEqualsUtf8(Utf8Bytes([$C2, $80]), EncodeCp($80), 'U+0080');
  CheckEqualsUtf8(Utf8Bytes([$C3, $A4]), EncodeCp($E4), 'U+00E4');
  CheckEqualsUtf8(Utf8Bytes([$DF, $BF]), EncodeCp($7FF), 'U+07FF');
  CheckEqualsUtf8(Utf8Bytes([$E0, $A0, $80]), EncodeCp($800), 'U+0800');
  CheckEqualsUtf8(Utf8Bytes([$E2, $82, $AC]), EncodeCp($20AC), 'U+20AC');
  CheckEqualsUtf8(Utf8Bytes([$ED, $9F, $BF]), EncodeCp($D7FF), 'U+D7FF');
  CheckEqualsUtf8(Utf8Bytes([$EE, $80, $80]), EncodeCp($E000), 'U+E000');
  CheckEqualsUtf8(Utf8Bytes([$EF, $BB, $BF]), EncodeCp($FEFF), 'U+FEFF');
  CheckEqualsUtf8(Utf8Bytes([$EF, $BF, $BF]), EncodeCp($FFFF), 'U+FFFF');
  CheckEqualsUtf8(Utf8Bytes([$F0, $90, $80, $80]), EncodeCp($10000), 'U+10000');
  CheckEqualsUtf8(Utf8Bytes([$F0, $9F, $98, $80]), EncodeCp($1F600), 'U+1F600');
  CheckEqualsUtf8(Utf8Bytes([$F4, $8F, $BF, $BF]), EncodeCp($10FFFF), 'U+10FFFF');
end;

procedure TestEncodeInvalid;
var
  Buf: array[0..3] of AnsiChar;
begin
  CheckEquals(0, LandrixXmlEncodeUtf8($D800, @Buf[0]), 'U+D800');
  CheckEquals(0, LandrixXmlEncodeUtf8($DBFF, @Buf[0]), 'U+DBFF');
  CheckEquals(0, LandrixXmlEncodeUtf8($DC00, @Buf[0]), 'U+DC00');
  CheckEquals(0, LandrixXmlEncodeUtf8($DFFF, @Buf[0]), 'U+DFFF');
  CheckEquals(0, LandrixXmlEncodeUtf8($110000, @Buf[0]), 'U+110000');
  CheckEquals(0, LandrixXmlEncodeUtf8($FFFFFFFF, @Buf[0]), 'U+FFFFFFFF');
end;

procedure TestDecodeValid;
var
  S: TLandrixXmlUtf8;
  CodePoint: Cardinal;
begin
  S := Utf8Bytes([$E2, $82, $AC, $41]);
  CheckEquals(3, LandrixXmlDecodeUtf8(PAnsiChar(S), Length(S), CodePoint), 'euro length');
  CheckEquals($20AC, Integer(CodePoint), 'euro code point');
  S := Utf8Bytes([$F4, $8F, $BF, $BF]);
  CheckEquals(4, LandrixXmlDecodeUtf8(PAnsiChar(S), Length(S), CodePoint), 'U+10FFFF length');
  CheckEquals($10FFFF, Integer(CodePoint), 'U+10FFFF code point');
  S := Utf8Bytes([$00]);
  CheckEquals(1, LandrixXmlDecodeUtf8(PAnsiChar(S), 1, CodePoint), 'NUL length');
  CheckEquals(0, Integer(CodePoint), 'NUL code point');
  CheckEquals(0, LandrixXmlDecodeUtf8(PAnsiChar(S), 0, CodePoint), 'Len = 0');
end;

procedure TestDecodeMalformed;
begin
  CheckMalformedUtf8(Utf8Bytes([$80]), 0, 'lone continuation 80');
  CheckMalformedUtf8(Utf8Bytes([$BF]), 0, 'lone continuation BF');
  CheckMalformedUtf8(Utf8Bytes([$C0, $80]), 0, 'overlong C0 80');
  CheckMalformedUtf8(Utf8Bytes([$C1, $BF]), 0, 'overlong C1 BF');
  CheckMalformedUtf8(Utf8Bytes([$E0, $80, $80]), 0, 'overlong E0 80 80');
  CheckMalformedUtf8(Utf8Bytes([$E0, $9F, $BF]), 0, 'overlong E0 9F BF');
  CheckMalformedUtf8(Utf8Bytes([$F0, $80, $80, $80]), 0, 'overlong F0 80 80 80');
  CheckMalformedUtf8(Utf8Bytes([$F0, $8F, $BF, $BF]), 0, 'overlong F0 8F BF BF');
  CheckMalformedUtf8(Utf8Bytes([$ED, $A0, $80]), 0, 'surrogate D800');
  CheckMalformedUtf8(Utf8Bytes([$ED, $BF, $BF]), 0, 'surrogate DFFF');
  CheckMalformedUtf8(Utf8Bytes([$ED, $A0, $BD, $ED, $B8, $80]), 0, 'CESU-8 pair');
  CheckMalformedUtf8(Utf8Bytes([$F4, $90, $80, $80]), 0, 'above U+10FFFF');
  CheckMalformedUtf8(Utf8Bytes([$F5, $80, $80, $80]), 0, 'lead F5');
  CheckMalformedUtf8(Utf8Bytes([$F8, $88, $80, $80, $80]), 0, '5-byte form');
  CheckMalformedUtf8(Utf8Bytes([$FE]), 0, 'byte FE');
  CheckMalformedUtf8(Utf8Bytes([$FF]), 0, 'byte FF');
  CheckMalformedUtf8(Utf8Bytes([$C3]), 0, 'truncated 2-byte');
  CheckMalformedUtf8(Utf8Bytes([$E2, $82]), 0, 'truncated 3-byte');
  CheckMalformedUtf8(Utf8Bytes([$F0, $9F, $98]), 0, 'truncated 4-byte');
  CheckMalformedUtf8(Utf8Bytes([$C3, $41]), 0, 'bad continuation');
  CheckMalformedUtf8(Utf8Bytes([$E2, $41, $AC]), 0, 'bad continuation 3-byte');
  CheckMalformedUtf8(Utf8Bytes([$41, $42, $C3]), 2, 'truncated at end');
  CheckMalformedUtf8(Utf8Bytes([$41, $C3, $A4, $80, $42]), 3, 'stray continuation after valid char');
end;

procedure TestCodePointRoundTripExhaustive;
var
  CodePoint, Decoded: Cardinal;
  Buf: array[0..3] of AnsiChar;
  N, Errors: Integer;
begin
  Errors := 0;
  CodePoint := 0;
  while CodePoint <= LandrixXmlMaxCodePoint do
  begin
    if (CodePoint < $D800) or (CodePoint > $DFFF) then
    begin
      N := LandrixXmlEncodeUtf8(CodePoint, @Buf[0]);
      if (N = 0) or (LandrixXmlDecodeUtf8(@Buf[0], N, Decoded) <> N) or
        (Decoded <> CodePoint) then
        Inc(Errors);
    end;
    Inc(CodePoint);
  end;
  CheckEquals(0, Errors, 'encode/decode round trip errors over all code points');
end;

procedure TestIsXmlChar;
begin
  Check(not LandrixXmlIsXmlChar($0), '#x0');
  Check(not LandrixXmlIsXmlChar($1), '#x1');
  Check(not LandrixXmlIsXmlChar($8), '#x8');
  Check(LandrixXmlIsXmlChar($9), '#x9');
  Check(LandrixXmlIsXmlChar($A), '#xA');
  Check(not LandrixXmlIsXmlChar($B), '#xB');
  Check(not LandrixXmlIsXmlChar($C), '#xC');
  Check(LandrixXmlIsXmlChar($D), '#xD');
  Check(not LandrixXmlIsXmlChar($1F), '#x1F');
  Check(LandrixXmlIsXmlChar($20), '#x20');
  Check(LandrixXmlIsXmlChar($7F), '#x7F');
  Check(LandrixXmlIsXmlChar($D7FF), '#xD7FF');
  Check(not LandrixXmlIsXmlChar($D800), '#xD800');
  Check(not LandrixXmlIsXmlChar($DFFF), '#xDFFF');
  Check(LandrixXmlIsXmlChar($E000), '#xE000');
  Check(LandrixXmlIsXmlChar($FFFD), '#xFFFD');
  Check(not LandrixXmlIsXmlChar($FFFE), '#xFFFE');
  Check(not LandrixXmlIsXmlChar($FFFF), '#xFFFF');
  Check(LandrixXmlIsXmlChar($10000), '#x10000');
  Check(LandrixXmlIsXmlChar($10FFFF), '#x10FFFF');
  Check(not LandrixXmlIsXmlChar($110000), '#x110000');
end;

{ --- validation ----------------------------------------------------------- }

procedure TestValidateUtf8;
var
  Bad: Integer;
begin
  Check(LandrixXmlValidateUtf8('', Bad), 'empty string is valid');
  CheckEquals(-1, Bad, 'BadOffset for valid input');
  Check(LandrixXmlValidateUtf8(Utf8Bytes([$41, $00, $42]), Bad), 'embedded NUL is valid UTF-8');
  Check(LandrixXmlValidateUtf8(Utf8Bytes([$EF, $BB, $BF, $41]), Bad), 'BOM is a valid character');
  Check(LandrixXmlValidateUtf8(Utf8Bytes([$EF, $BF, $BF]), Bad), 'U+FFFF is valid UTF-8 (not an XML char)');
  Check(LandrixXmlValidateUtf8(Utf8Bytes([$F0, $9F, $98, $80, $C3, $A4]), Bad), 'emoji + umlaut');
  Check(not LandrixXmlValidateUtf8Buf(PAnsiChar(Utf8Bytes([$41, $FF])), 2, Bad), 'buffer variant');
  CheckEquals(1, Bad, 'buffer variant offset');
  Check(LandrixXmlValidateUtf8Buf(nil, 0, Bad), 'nil buffer with length 0');
end;

{ --- conversion ----------------------------------------------------------- }

procedure TestUtf8ToWide;
begin
  CheckEqualsWide('', LandrixXmlUtf8ToWide(''), 'empty');
  CheckEqualsWide(Wide([$41, $42]), LandrixXmlUtf8ToWide(Utf8Bytes([$41, $42])), 'ASCII');
  CheckEqualsWide(Wide([$E4, $20AC]), LandrixXmlUtf8ToWide(Utf8Bytes([$C3, $A4, $E2, $82, $AC])), 'umlaut + euro');
  CheckEqualsWide(Wide([$D83D, $DE00]), LandrixXmlUtf8ToWide(Utf8Bytes([$F0, $9F, $98, $80])), 'U+1F600 surrogate pair');
  CheckEqualsWide(Wide([$D800, $DC00]), LandrixXmlUtf8ToWide(Utf8Bytes([$F0, $90, $80, $80])), 'U+10000');
  CheckEqualsWide(Wide([$DBFF, $DFFF]), LandrixXmlUtf8ToWide(Utf8Bytes([$F4, $8F, $BF, $BF])), 'U+10FFFF');
  CheckEqualsWide(Wide([$41, $0, $42]), LandrixXmlUtf8ToWide(Utf8Bytes([$41, $00, $42])), 'embedded NUL kept');
  CheckEqualsWide(Wide([$FEFF]), LandrixXmlUtf8ToWide(Utf8Bytes([$EF, $BB, $BF])), 'BOM character kept');
end;

procedure TestWideToUtf8;
begin
  CheckEqualsUtf8('', LandrixXmlWideToUtf8(''), 'empty');
  CheckEqualsUtf8(Utf8Bytes([$41, $42]), LandrixXmlWideToUtf8(Wide([$41, $42])), 'ASCII');
  CheckEqualsUtf8(Utf8Bytes([$C3, $A4, $E2, $82, $AC]), LandrixXmlWideToUtf8(Wide([$E4, $20AC])), 'umlaut + euro');
  CheckEqualsUtf8(Utf8Bytes([$F0, $9F, $98, $80]), LandrixXmlWideToUtf8(Wide([$D83D, $DE00])), 'surrogate pair');
  CheckEqualsUtf8(Utf8Bytes([$F4, $8F, $BF, $BF]), LandrixXmlWideToUtf8(Wide([$DBFF, $DFFF])), 'U+10FFFF');
  CheckEqualsUtf8(Utf8Bytes([$41, $00]), LandrixXmlWideToUtf8(Wide([$41, $0])), 'embedded NUL kept');
  CheckEqualsUtf8(Utf8Bytes([$EF, $BF, $BF]), LandrixXmlWideToUtf8(Wide([$FFFF])), 'U+FFFF');
end;

procedure TestWideToUtf8Invalid;
begin
  CheckInvalidUtf16(Wide([$D800]), 0, 'lone high surrogate');
  CheckInvalidUtf16(Wide([$DC00]), 0, 'lone low surrogate');
  CheckInvalidUtf16(Wide([$41, $D83D]), 1, 'high surrogate at end');
  CheckInvalidUtf16(Wide([$D83D, $41]), 0, 'high surrogate followed by ASCII');
  CheckInvalidUtf16(Wide([$D83D, $D83D, $DE00]), 0, 'high high low');
  CheckInvalidUtf16(Wide([$41, $DE00, $D83D]), 1, 'reversed pair');
end;

procedure TestWideRoundTripAllCodePoints;
var
  Buf: TLandrixXmlBuffer;
  CodePoint: Cardinal;
  Utf8, Back: TLandrixXmlUtf8;
  W: TLandrixXmlWide;
begin
  Buf := TLandrixXmlBuffer.Create;
  try
    CodePoint := 0;
    while CodePoint <= LandrixXmlMaxCodePoint do
    begin
      if (CodePoint < $D800) or (CodePoint > $DFFF) then
        Buf.AppendCodePoint(CodePoint);
      Inc(CodePoint);
    end;
    Utf8 := Buf.AsUtf8;
  finally
    Buf.Free;
  end;
  W := LandrixXmlUtf8ToWide(Utf8);
  { BMP without surrogates: $10000 - $800 units; astral: 2 units each }
  CheckEquals(($10000 - $800) + 2 * ($110000 - $10000), Length(W), 'UTF-16 length');
  Back := LandrixXmlWideToUtf8(W);
  Check(Length(Back) = Length(Utf8), 'UTF-8 length after round trip');
  Check((Length(Back) = Length(Utf8)) and SameMemory(PAnsiChar(Back), PAnsiChar(Utf8), Length(Utf8)),
    'UTF-8 -> UTF-16 -> UTF-8 is lossless for all code points');
end;

procedure TestNativeString;
var
  S: string;
  U: TLandrixXmlUtf8;
begin
  CheckEqualsStr('', LandrixXmlUtf8ToString(''), 'empty to string');
  CheckEqualsUtf8('', LandrixXmlStringToUtf8(''), 'empty from string');
  CheckEqualsStr('AB<>&', LandrixXmlUtf8ToString(Utf8Bytes([$41, $42, $3C, $3E, $26])), 'ASCII to string');
  CheckEqualsUtf8(Utf8Bytes([$41, $42, $3C]), LandrixXmlStringToUtf8('AB<'), 'ASCII from string');

  { umlaut a, euro, U+1F600 }
  U := Utf8Bytes([$C3, $A4, $E2, $82, $AC, $F0, $9F, $98, $80]);
  S := LandrixXmlUtf8ToString(U);
{$IFDEF LANDRIXXML_UNICODE}
  try
    LandrixXmlStringToUtf8(string(Wide([$41, $D800])));
    FailNotRaised('ELandrixXmlError for lone surrogate in string');
  except
    on E: ELandrixXmlError do
    begin
      CheckErrorCode(xecInvalidUnicode, E.Code, 'lone surrogate in string');
      CheckEqualsInt64(1, E.Offset, 'lone surrogate offset');
    end;
  end;
  CheckEquals(4, Length(S), 'Unicode Delphi: 4 UTF-16 units');
  CheckEquals($E4, Ord(S[1]), 'Unicode Delphi: umlaut');
  CheckEquals($20AC, Ord(S[2]), 'Unicode Delphi: euro');
  CheckEqualsUtf8(U, LandrixXmlStringToUtf8(S), 'Unicode Delphi: lossless round trip');
{$ELSE}
  {$IFDEF FPC}
  { the UTF-8 pass-through branch is tested in Base.NativeStringFpcUtf8 }
  if DefaultSystemCodePage <> CP_UTF8 then
  begin
    Check(Length(S) >= 3, 'FPC non-UTF-8 code page: converted');
    if DefaultSystemCodePage = 1252 then
    begin
      CheckEquals($E4, Ord(S[1]), 'FPC cp1252: umlaut');
      CheckEquals($80, Ord(S[2]), 'FPC cp1252: euro');
      CheckEqualsUtf8(Copy(U, 1, 5), LandrixXmlStringToUtf8(Copy(S, 1, 2)),
        'FPC cp1252: representable characters round trip');
    end;
  end;
  {$ELSE}
  { Delphi 6-2007: system code page, characters may become '?' }
  Check(Length(S) >= 3, 'Ansi Delphi: converted');
  if (Length(S) >= 2) and (S[1] <> '?') and (S[2] <> '?') then
    CheckEqualsUtf8(Copy(U, 1, 5), LandrixXmlStringToUtf8(Copy(S, 1, 2)),
      'Ansi Delphi: representable characters round trip');
  {$ENDIF}
{$ENDIF}

  try
    LandrixXmlUtf8ToString(Utf8Bytes([$41, $FF]));
    FailNotRaised('ELandrixXmlError for invalid UTF-8 to string');
  except
    on E: ELandrixXmlError do
      CheckErrorCode(xecInvalidUnicode, E.Code, 'invalid UTF-8 to string');
  end;
end;

{$IFDEF FPC}
{ Forces DefaultSystemCodePage = CP_UTF8 (as Lazarus/LazUTF8 does) so that the
  byte pass-through branches run on every FPC target. }
procedure TestNativeStringFpcUtf8;
var
  Saved: TSystemCodePage;
  S: string;
  U: TLandrixXmlUtf8;
begin
  U := Utf8Bytes([$C3, $A4, $E2, $82, $AC, $F0, $9F, $98, $80]);
  Saved := DefaultSystemCodePage;
  DefaultSystemCodePage := CP_UTF8;
  try
    S := LandrixXmlUtf8ToString(U);
    CheckEquals(Length(U), Length(S), 'pass-through length');
    Check(SameMemory(PAnsiChar(U), PAnsiChar(S), Length(U)), 'pass-through bytes');
    CheckEqualsUtf8(U, LandrixXmlStringToUtf8(S), 'lossless round trip');
    try
      LandrixXmlUtf8ToString(Utf8Bytes([$41, $C3]));
      FailNotRaised('ELandrixXmlError for invalid UTF-8 (pass-through)');
    except
      on E: ELandrixXmlError do
      begin
        CheckErrorCode(xecInvalidUnicode, E.Code, 'invalid UTF-8 (pass-through)');
        CheckEqualsInt64(1, E.Offset, 'invalid UTF-8 offset (pass-through)');
      end;
    end;
  finally
    DefaultSystemCodePage := Saved;
  end;
  { a string tagged with CP_UTF8 must be read as UTF-8 whatever the default }
  if StringCodePage(S) = CP_UTF8 then
    CheckEqualsUtf8(U, LandrixXmlStringToUtf8(S), 'CP_UTF8-tagged string after restoring the default')
  else
    WriteLn('  info: pass-through string carries code page ', StringCodePage(S));
end;
{$ENDIF}

procedure TestBufToUtf8;
var
  Src: TLandrixXmlUtf8;
begin
  Src := Utf8Bytes([$41, $C3, $A4]);
  CheckEqualsUtf8(Src, LandrixXmlBufToUtf8(PAnsiChar(Src), 3), 'valid copy');
  CheckEqualsUtf8('', LandrixXmlBufToUtf8(nil, 0), 'empty');
  try
    LandrixXmlBufToUtf8(PAnsiChar(Src), 2);
    FailNotRaised('ELandrixXmlError for truncated buffer');
  except
    on E: ELandrixXmlError do
    begin
      CheckErrorCode(xecInvalidUnicode, E.Code, 'truncated buffer');
      CheckEqualsInt64(1, E.Offset, 'truncated buffer offset');
    end;
  end;
  try
    LandrixXmlBufToUtf8(PAnsiChar(Src), -1);
    FailNotRaised('ELandrixXmlError for negative length');
  except
    on E: ELandrixXmlError do
      CheckErrorCode(xecInvalidArgument, E.Code, 'negative length');
  end;
end;

{ --- exception and diagnostics -------------------------------------------- }

procedure TestErrorFields;
var
  E: ELandrixXmlError;
begin
  E := ELandrixXmlError.CreateAt(xecSyntax, 'Boom', 3, 7, 120);
  try
    CheckEqualsStr('Boom (line 3, column 7, offset 120)', E.Message, 'message with position');
    CheckErrorCode(xecSyntax, E.Code, 'code');
    CheckEquals(3, E.Line, 'line');
    CheckEquals(7, E.Column, 'column');
    CheckEqualsInt64(120, E.Offset, 'offset');
  finally
    E.Free;
  end;

  E := ELandrixXmlError.CreateAt(xecSyntax, 'Boom', 0, 0, 0);
  try
    CheckEqualsStr('Boom (offset 0)', E.Message, 'offset 0 is a valid position');
    CheckEqualsInt64(0, E.Offset, 'offset 0');
    CheckEquals(0, E.Line, 'unknown line');
  finally
    E.Free;
  end;

  E := ELandrixXmlError.CreateAt(xecSyntax, 'L', 3, 0, -1);
  try
    CheckEqualsStr('L (line 3)', E.Message, 'line only');
  finally
    E.Free;
  end;

  E := ELandrixXmlError.CreateAt(xecLimit, 'Big', 0, 0, 5000000000);
  try
    CheckEqualsInt64(5000000000, E.Offset, 'offset beyond 4 GB');
  finally
    E.Free;
  end;

  E := ELandrixXmlError.CreateAt(xecSyntax, 'NoPos', 0, 0, -1);
  try
    CheckEqualsStr('NoPos', E.Message, 'no position suffix');
    CheckEqualsInt64(-1, E.Offset, 'unknown offset');
  finally
    E.Free;
  end;

  E := ELandrixXmlError.CreateCode(xecWrite, 'W');
  try
    CheckErrorCode(xecWrite, E.Code, 'CreateCode code');
    CheckEqualsInt64(-1, E.Offset, 'CreateCode offset unknown');
  finally
    E.Free;
  end;

  E := ELandrixXmlError.Create('Plain');
  try
    CheckErrorCode(xecNone, E.Code, 'plain Create code');
    CheckEqualsInt64(-1, E.Offset, 'plain Create offset unknown');
    CheckEquals(0, E.Line, 'plain Create line');
    CheckEquals(0, E.Column, 'plain Create column');
  finally
    E.Free;
  end;
end;

procedure TestErrorCodeOrdinals;
begin
  { the enum is append-only: these values must never change }
  CheckEquals(0, Ord(xecNone), 'xecNone');
  CheckEquals(1, Ord(xecGeneral), 'xecGeneral');
  CheckEquals(2, Ord(xecInvalidArgument), 'xecInvalidArgument');
  CheckEquals(3, Ord(xecInvalidOperation), 'xecInvalidOperation');
  CheckEquals(4, Ord(xecInvalidUnicode), 'xecInvalidUnicode');
  CheckEquals(5, Ord(xecEncoding), 'xecEncoding');
  CheckEquals(6, Ord(xecSyntax), 'xecSyntax');
  CheckEquals(7, Ord(xecNamespace), 'xecNamespace');
  CheckEquals(8, Ord(xecInvalidChar), 'xecInvalidChar');
  CheckEquals(9, Ord(xecLimit), 'xecLimit');
  CheckEquals(10, Ord(xecWrite), 'xecWrite');
  CheckEquals(11, Ord(xecConversion), 'xecConversion');
  CheckEquals(12, Ord(xecUnexpectedElement), 'xecUnexpectedElement');
end;

procedure TestEscapeForMessage;
begin
  CheckEqualsStr('abc', LandrixXmlEscapeForMessage(Utf8Bytes([$61, $62, $63]), 10), 'ASCII');
  CheckEqualsStr('aU+00E4', LandrixXmlEscapeForMessage(Utf8Bytes([$61, $C3, $A4]), 10), 'umlaut');
  CheckEqualsStr('U+000AU+0009', LandrixXmlEscapeForMessage(Utf8Bytes([$0A, $09]), 10), 'controls');
  CheckEqualsStr('U+1F600', LandrixXmlEscapeForMessage(Utf8Bytes([$F0, $9F, $98, $80]), 10), 'emoji');
  CheckEqualsStr('\xC3a', LandrixXmlEscapeForMessage(Utf8Bytes([$C3, $61]), 10), 'invalid byte');
  CheckEqualsStr('ab...', LandrixXmlEscapeForMessage(Utf8Bytes([$61, $62, $63, $64]), 2), 'truncated');
  CheckEqualsStr('ab', LandrixXmlEscapeForMessage(Utf8Bytes([$61, $62]), 2), 'exact length not truncated');
  CheckEqualsStr('', LandrixXmlEscapeForMessage('', 10), 'empty');
  CheckEqualsStr('...', LandrixXmlEscapeForMessage(Utf8Bytes([$61]), 0), 'MaxChars = 0');
end;

{ --- buffer ---------------------------------------------------------------- }

procedure TestBufferEmpty;
var
  Buf: TLandrixXmlBuffer;
begin
  Buf := TLandrixXmlBuffer.Create;
  try
    Check(Buf.Data = nil, 'Data is nil before first allocation');
    CheckEquals(0, Buf.Size, 'Size');
    CheckEquals(0, Buf.Capacity, 'Capacity');
    CheckEqualsUtf8('', Buf.AsUtf8, 'AsUtf8 of empty buffer');
    Buf.Append(Buf, 0);
    Buf.AppendUtf8('');
    Buf.AppendAscii('');
    Buf.Clear;
    Buf.Truncate(0);
    Check(Buf.Data = nil, 'no allocation for empty operations');
  finally
    Buf.Free;
  end;
end;

procedure TestBufferAppendAndSentinel;
var
  Buf: TLandrixXmlBuffer;
  I: Integer;
begin
  Buf := TLandrixXmlBuffer.Create;
  try
    Buf.AppendByte($41);
    CheckEquals(1, Buf.Size, 'Size after AppendByte');
    Check(Buf.Capacity >= 256, 'minimum capacity');
    CheckEquals(0, Ord(Buf.Data[1]), 'sentinel after AppendByte');
    Buf.AppendUtf8(Utf8Bytes([$C3, $A4]));
    Buf.AppendAscii('xyz');
    CheckEqualsUtf8(Utf8Bytes([$41, $C3, $A4, $78, $79, $7A]), Buf.AsUtf8, 'content');
    CheckEquals(0, Ord(Buf.Data[Buf.Size]), 'sentinel after AppendAscii');
    for I := 1 to 1000 do
      Buf.AppendByte(Byte(Ord('0') + I mod 10));
    CheckEquals(1006, Buf.Size, 'Size after growth');
    CheckEquals(0, Ord(Buf.Data[Buf.Size]), 'sentinel after growth');
    CheckEquals(Ord('0'), Ord(Buf.Data[1005]), 'last byte');
    Check(Buf.Capacity >= Buf.Size, 'Capacity >= Size');
  finally
    Buf.Free;
  end;
end;

procedure TestBufferClearTruncateReserve;
var
  Buf: TLandrixXmlBuffer;
  Cap: Integer;
begin
  Buf := TLandrixXmlBuffer.Create;
  try
    Buf.AppendAscii('hello');
    Cap := Buf.Capacity;
    Buf.Truncate(2);
    CheckEqualsUtf8(Utf8Bytes([$68, $65]), Buf.AsUtf8, 'Truncate');
    CheckEquals(0, Ord(Buf.Data[2]), 'sentinel after Truncate');
    Buf.Clear;
    CheckEquals(0, Buf.Size, 'Size after Clear');
    CheckEquals(Cap, Buf.Capacity, 'Clear keeps capacity');
    CheckEquals(0, Ord(Buf.Data[0]), 'sentinel after Clear');
    Buf.Reserve(10000);
    Check(Buf.Capacity >= 10000, 'Reserve');
    CheckEquals(0, Ord(Buf.Data[0]), 'sentinel after Reserve');
    Cap := Buf.Capacity;
    Buf.Reserve(5);
    CheckEquals(Cap, Buf.Capacity, 'Reserve never shrinks');
  finally
    Buf.Free;
  end;
end;

procedure TestBufferSelfAppend;
var
  Buf: TLandrixXmlBuffer;
  I: Integer;
begin
  Buf := TLandrixXmlBuffer.Create;
  try
    Buf.AppendAscii('ab');
    { doubling the content until the buffer must reallocate several times }
    for I := 1 to 12 do
      Buf.Append(Buf.Data^, Buf.Size);
    CheckEquals(2 shl 12, Buf.Size, 'Size after self-appends');
    Check((Buf.Data[0] = 'a') and (Buf.Data[1] = 'b'), 'start intact');
    Check((Buf.Data[Buf.Size - 2] = 'a') and (Buf.Data[Buf.Size - 1] = 'b'), 'end intact');
    I := 0;
    while (I < Buf.Size) and (Buf.Data[I] = AnsiChar(Ord('a') + I mod 2)) do
      Inc(I);
    CheckEquals(Buf.Size, I, 'every byte intact');
    { append a part of itself }
    Buf.Clear;
    Buf.AppendAscii('0123456789');
    Buf.Append(Buf.Data[3], 4);
    CheckEqualsUtf8(Utf8Bytes([$30, $31, $32, $33, $34, $35, $36, $37, $38, $39, $33, $34, $35, $36]),
      Buf.AsUtf8, 'partial self-append');
  finally
    Buf.Free;
  end;
end;

procedure TestBufferAppendCodePoint;
var
  Buf: TLandrixXmlBuffer;
begin
  Buf := TLandrixXmlBuffer.Create;
  try
    Buf.AppendCodePoint($41);
    Buf.AppendCodePoint($E4);
    Buf.AppendCodePoint($20AC);
    Buf.AppendCodePoint($1F600);
    CheckEqualsUtf8(Utf8Bytes([$41, $C3, $A4, $E2, $82, $AC, $F0, $9F, $98, $80]),
      Buf.AsUtf8, 'code points');
    try
      Buf.AppendCodePoint($D800);
      FailNotRaised('ELandrixXmlError for surrogate code point');
    except
      on E: ELandrixXmlError do
        CheckErrorCode(xecInvalidUnicode, E.Code, 'surrogate code point');
    end;
    try
      Buf.AppendCodePoint($110000);
      FailNotRaised('ELandrixXmlError for code point above U+10FFFF');
    except
      on E: ELandrixXmlError do
        CheckErrorCode(xecInvalidUnicode, E.Code, 'code point above U+10FFFF');
    end;
    CheckEquals(10, Buf.Size, 'failed appends leave the buffer unchanged');
  finally
    Buf.Free;
  end;
end;

procedure TestBufferInvalidArguments;
var
  Buf: TLandrixXmlBuffer;
begin
  Buf := TLandrixXmlBuffer.Create;
  try
    Buf.AppendAscii('abc');
    try
      Buf.Append(Buf, -1);
      FailNotRaised('ELandrixXmlError for negative count');
    except
      on E: ELandrixXmlError do
        CheckErrorCode(xecInvalidArgument, E.Code, 'negative count');
    end;
    try
      Buf.Truncate(4);
      FailNotRaised('ELandrixXmlError for Truncate beyond Size');
    except
      on E: ELandrixXmlError do
        CheckErrorCode(xecInvalidArgument, E.Code, 'Truncate beyond Size');
    end;
    try
      Buf.Truncate(-1);
      FailNotRaised('ELandrixXmlError for negative Truncate');
    except
      on E: ELandrixXmlError do
        CheckErrorCode(xecInvalidArgument, E.Code, 'negative Truncate');
    end;
    try
      Buf.Reserve(MaxInt);
      FailNotRaised('ELandrixXmlError for Reserve(MaxInt)');
    except
      on E: ELandrixXmlError do
        CheckErrorCode(xecLimit, E.Code, 'Reserve(MaxInt)');
    end;
    try
      Buf.Reserve(-1);
      FailNotRaised('ELandrixXmlError for negative Reserve');
    except
      on E: ELandrixXmlError do
        CheckErrorCode(xecInvalidArgument, E.Code, 'negative Reserve');
    end;
    try
      Buf.AppendAscii(Bytes([$61, $E4]));
      FailNotRaised('ELandrixXmlError for non-ASCII in AppendAscii');
    except
      on E: ELandrixXmlError do
        CheckErrorCode(xecInvalidArgument, E.Code, 'non-ASCII in AppendAscii');
    end;
    try
      Buf.Append(Buf, MaxInt);
      FailNotRaised('ELandrixXmlError for size overflow');
    except
      on E: ELandrixXmlError do
        CheckErrorCode(xecLimit, E.Code, 'size overflow');
    end;
    CheckEqualsUtf8(Utf8Bytes([$61, $62, $63]), Buf.AsUtf8, 'content unchanged after errors');
  finally
    Buf.Free;
  end;
end;

procedure TestBufferStreamAndCopy;
var
  Buf: TLandrixXmlBuffer;
  Stream: TMemoryStream;
  Copy1: TLandrixXmlUtf8;
  Prefix: AnsiString;
begin
  Buf := TLandrixXmlBuffer.Create;
  Stream := TMemoryStream.Create;
  try
    Prefix := 'xy';
    Stream.WriteBuffer(PAnsiChar(Prefix)^, 2);
    Buf.AppendAscii('abc');
    Buf.WriteToStream(Stream);
    CheckEquals(5, Integer(Stream.Size), 'stream size');
    CheckEquals(5, Integer(Stream.Position), 'stream position');
    Check(SameMemory(Stream.Memory, PAnsiChar(AnsiString('xyabc')), 5), 'stream content');

    Buf.Clear;
    Buf.WriteToStream(Stream);
    CheckEquals(5, Integer(Stream.Size), 'empty buffer writes nothing');
    Buf.AppendAscii('abc');

    Copy1 := Buf.AsUtf8;
    Buf.Clear;
    Buf.AppendAscii('zzz');
    CheckEqualsUtf8(Utf8Bytes([$61, $62, $63]), Copy1, 'AsUtf8 returns an independent copy');
  finally
    Stream.Free;
    Buf.Free;
  end;
end;

procedure TestBufferExtend;
var
  Buf: TLandrixXmlBuffer;
  P: PAnsiChar;
begin
  Buf := TLandrixXmlBuffer.Create;
  try
    Check(Buf.Extend(0) = nil, 'Extend(0) returns nil');
    Buf.AppendAscii('ab');
    P := Buf.Extend(3);
    CheckEquals(5, Buf.Size, 'Size after Extend');
    P[0] := 'x';
    P[1] := 'y';
    P[2] := 'z';
    CheckEqualsUtf8(Utf8Bytes([$61, $62, $78, $79, $7A]), Buf.AsUtf8, 'content after Extend');
    CheckEquals(0, Ord(Buf.Data[5]), 'sentinel after Extend');
    P := Buf.Extend(10000);
    Check(P = Buf.Data + 5, 'Extend returns the new region after growth');
    CheckEquals(10005, Buf.Size, 'Size after growing Extend');
    CheckEquals(0, Ord(Buf.Data[10005]), 'sentinel after growing Extend');
    try
      Buf.Extend(-1);
      FailNotRaised('ELandrixXmlError for negative Extend');
    except
      on E: ELandrixXmlError do
        CheckErrorCode(xecInvalidArgument, E.Code, 'negative Extend');
    end;
    try
      Buf.Extend(MaxInt);
      FailNotRaised('ELandrixXmlError for Extend overflow');
    except
      on E: ELandrixXmlError do
        CheckErrorCode(xecLimit, E.Code, 'Extend overflow');
    end;
    CheckEquals(10005, Buf.Size, 'failed Extend leaves Size unchanged');
  finally
    Buf.Free;
  end;
end;

procedure TestBufferLarge;
var
  Buf: TLandrixXmlBuffer;
  Block: AnsiString;
  I: Integer;
begin
  Buf := TLandrixXmlBuffer.Create;
  try
    Block := Bytes([$3C, $61, $3E]);
    for I := 1 to 1000000 do
      Buf.Append(PAnsiChar(Block)^, 3);
    CheckEquals(3000000, Buf.Size, 'Size after 1M appends');
    CheckEquals($3C, Ord(Buf.Data[2999997]), 'last block start');
    CheckEquals(0, Ord(Buf.Data[3000000]), 'sentinel');
  finally
    Buf.Free;
  end;
end;

procedure Register;
begin
  RegisterTest('Base.EncodeBoundaries', TestEncodeBoundaries);
  RegisterTest('Base.EncodeInvalid', TestEncodeInvalid);
  RegisterTest('Base.DecodeValid', TestDecodeValid);
  RegisterTest('Base.DecodeMalformed', TestDecodeMalformed);
  RegisterTest('Base.CodePointRoundTripExhaustive', TestCodePointRoundTripExhaustive);
  RegisterTest('Base.IsXmlChar', TestIsXmlChar);
  RegisterTest('Base.ValidateUtf8', TestValidateUtf8);
  RegisterTest('Base.Utf8ToWide', TestUtf8ToWide);
  RegisterTest('Base.WideToUtf8', TestWideToUtf8);
  RegisterTest('Base.WideToUtf8Invalid', TestWideToUtf8Invalid);
  RegisterTest('Base.WideRoundTripAllCodePoints', TestWideRoundTripAllCodePoints);
  RegisterTest('Base.NativeString', TestNativeString);
{$IFDEF FPC}
  RegisterTest('Base.NativeStringFpcUtf8', TestNativeStringFpcUtf8);
{$ENDIF}
  RegisterTest('Base.BufToUtf8', TestBufToUtf8);
  RegisterTest('Base.ErrorFields', TestErrorFields);
  RegisterTest('Base.ErrorCodeOrdinals', TestErrorCodeOrdinals);
  RegisterTest('Base.EscapeForMessage', TestEscapeForMessage);
  RegisterTest('Buffer.Empty', TestBufferEmpty);
  RegisterTest('Buffer.AppendAndSentinel', TestBufferAppendAndSentinel);
  RegisterTest('Buffer.ClearTruncateReserve', TestBufferClearTruncateReserve);
  RegisterTest('Buffer.SelfAppend', TestBufferSelfAppend);
  RegisterTest('Buffer.AppendCodePoint', TestBufferAppendCodePoint);
  RegisterTest('Buffer.InvalidArguments', TestBufferInvalidArguments);
  RegisterTest('Buffer.StreamAndCopy', TestBufferStreamAndCopy);
  RegisterTest('Buffer.Extend', TestBufferExtend);
  RegisterTest('Buffer.Large', TestBufferLarge);
end;

end.
