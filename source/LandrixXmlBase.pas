{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Base unit: string types, strict UTF-8/UTF-16 coding, the single conversion
  point between UTF-8, wide and native strings, the byte buffer and the
  exception class.

  String types
  ------------
  TLandrixXmlUtf8  UTF-8 bytes. AnsiString on Delphi 6-2007, UTF8String on
                   Delphi 2009+ and FPC. Lossless.
  TLandrixXmlWide  UTF-16. WideString on Delphi 6-2007, UnicodeString on
                   Delphi 2009+ and FPC. Lossless.
  string           Native string. Lossless on Delphi 2009+. On Delphi
                   6-2007 converted to the system code page: characters the
                   code page cannot represent become '?'. On FPC passed
                   through unchanged when the code page is UTF-8, otherwise
                   converted by the RTL (on Unix this needs the cwstring unit
                   in the application, else it is lossy).

  Invalid Unicode (malformed UTF-8, unpaired UTF-16 surrogates) is never
  replaced silently: the conversion routines raise ELandrixXmlError with
  Code = xecInvalidUnicode and Offset = position inside the argument (bytes
  for UTF-8 input, code units for UTF-16 input). }

unit LandrixXmlBase;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  Classes;

const
  LandrixXmlVersion = '0.2.0';

  { Highest Unicode code point. }
  LandrixXmlMaxCodePoint = $10FFFF;

  { Namespace names bound to the reserved prefixes xml and xmlns. }
  LandrixXmlNamespaceXml = 'http://www.w3.org/XML/1998/namespace';
  LandrixXmlNamespaceXmlns = 'http://www.w3.org/2000/xmlns/';

type
{$IFDEF LANDRIXXML_UNICODE}
  TLandrixXmlUtf8 = UTF8String;
  TLandrixXmlWide = UnicodeString;
{$ELSE}
  {$IFDEF FPC}
  TLandrixXmlUtf8 = UTF8String;
  TLandrixXmlWide = UnicodeString;
  {$ELSE}
  TLandrixXmlUtf8 = AnsiString;
  TLandrixXmlWide = WideString;
  {$ENDIF}
{$ENDIF}

  TLandrixXmlUtf8Array = array of TLandrixXmlUtf8;

  { Error categories. Append-only: never reorder or remove values. }
  TLandrixXmlErrorCode = (
    xecNone,             { no error / not set }
    xecGeneral,          { anything not covered below }
    xecInvalidArgument,  { API misuse: bad parameter value }
    xecInvalidOperation, { API misuse: call not allowed in this state }
    xecInvalidUnicode,   { malformed UTF-8 or unpaired UTF-16 surrogate }
    xecEncoding,         { unsupported or inconsistent input encoding }
    xecSyntax,           { input is not well-formed XML }
    xecNamespace,        { namespace error (undeclared prefix, ...) }
    xecInvalidChar,      { character not allowed by XML 1.0 }
    xecLimit,            { resource limit exceeded (depth, size, ...) }
    xecWrite,            { the writer was asked to produce invalid XML }
    xecConversion,       { a value has no valid xs:* lexical form }
    xecUnexpectedElement, { an element where the caller expects text only }
    xecArithmetic,       { division by zero or an arithmetic result out of range }
    xecRegex,            { invalid regular expression or replacement string }
    xecUnsupported,      { valid input using a construct this library does not support }
    xecSchema            { an XML Schema that is invalid or cannot be resolved }
  );

  { All errors raised by LandrixXml. Line and Column are 1-based (Column in
    Unicode code points), 0 = unknown. Offset is a 0-based byte offset into
    the original input, -1 = unknown. Exception: errors raised by the
    string conversion routines report the position inside their argument
    (bytes for UTF-8, code units for UTF-16). Messages are English ASCII text for
    diagnostics; do not parse them, use Code instead. }
  ELandrixXmlError = class(Exception)
  private
    FCode: TLandrixXmlErrorCode;
    FLine: Integer;
    FColumn: Integer;
    FOffsetPlusOne: Int64; { 0 = unknown, so plain Create yields -1 }
    function GetOffset: Int64;
  public
    constructor CreateCode(ACode: TLandrixXmlErrorCode; const Msg: string);
    { The position is appended to the message, e.g.
      'Unexpected end of input (line 3, column 7, offset 120)'. }
    constructor CreateAt(ACode: TLandrixXmlErrorCode; const Msg: string;
      ALine, AColumn: Integer; AOffset: Int64);
    property Code: TLandrixXmlErrorCode read FCode;
    property Line: Integer read FLine;
    property Column: Integer read FColumn;
    property Offset: Int64 read GetOffset;
  end;

  { Growable byte buffer. Data is always followed by a #0 byte (not counted
    in Size), so byte scanners can use it as a sentinel. Data is nil until
    the first allocation and may move whenever the buffer grows. Appending
    from the buffer's own memory is safe. Limit: Size < 2 GB. }
  TLandrixXmlBuffer = class
  private
    FData: PAnsiChar;
    FSize: Integer;
    FCapacity: Integer;
  public
    destructor Destroy; override;
    { Sets Size to 0 and keeps the allocated memory. Like Truncate it
      writes the #0 sentinel at the new end, so do not use the old content
      afterwards (e.g. as source of an Append). }
    procedure Clear;
    { Ensures Capacity >= MinCapacity. }
    procedure Reserve(MinCapacity: Integer);
    { Shortens the content to NewSize bytes (0 <= NewSize <= Size). }
    procedure Truncate(NewSize: Integer);
    procedure Append(const Data; Count: Integer);
    procedure AppendByte(B: Byte);
    { Grows Size by Count bytes and returns a pointer to the new,
      uninitialised region (or nil for Count = 0). The pointer is valid until
      the next call that may grow the buffer. }
    function Extend(Count: Integer): PAnsiChar;
    procedure AppendUtf8(const S: TLandrixXmlUtf8);
    { Appends 7-bit ASCII text; raises on bytes >= $80. }
    procedure AppendAscii(const S: AnsiString);
    { Appends the UTF-8 encoding of CodePoint; raises on surrogates and
      values above U+10FFFF. }
    procedure AppendCodePoint(CodePoint: Cardinal);
    { Returns a copy of the content. The bytes are not validated. }
    function AsUtf8: TLandrixXmlUtf8;
    { Writes the content at the stream's current position. }
    procedure WriteToStream(Stream: TStream);
    property Data: PAnsiChar read FData;
    property Size: Integer read FSize;
    property Capacity: Integer read FCapacity;
  end;

{ --- Code point primitives --------------------------------------------- }

{ Decodes one strictly valid UTF-8 sequence at P (Len bytes available).
  Returns the number of bytes consumed (1-4), or 0 if the sequence is
  malformed, overlong, a surrogate, above U+10FFFF or truncated. }
function LandrixXmlDecodeUtf8(P: PAnsiChar; Len: Integer;
  out CodePoint: Cardinal): Integer;

{ Writes the UTF-8 encoding of CodePoint to Dest (room for 4 bytes needed).
  Returns the number of bytes written, or 0 for surrogates and values above
  U+10FFFF. }
function LandrixXmlEncodeUtf8(CodePoint: Cardinal; Dest: PAnsiChar): Integer;

{ True if CodePoint matches the XML 1.0 Char production:
  #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF] }
function LandrixXmlIsXmlChar(CodePoint: Cardinal): Boolean;

{ XML 1.0 fifth edition NameStartChar and NameChar. The colon is included
  (namespace rules are checked separately). }
function LandrixXmlIsNameStartChar(CodePoint: Cardinal): Boolean;
function LandrixXmlIsNameChar(CodePoint: Cardinal): Boolean;

{ Checks that the Len bytes at P form a strictly valid UTF-8 XML Name.
  Returns the offset of the first offending byte, or -1 if valid (an empty
  name reports offset 0). }
function LandrixXmlCheckName(P: PAnsiChar; Len: Integer): Integer;

{ FNV-1a hash over Len bytes, continuing from Seed (start with
  LandrixXmlHashSeed). Used for duplicate checks and name tables. }
const
  LandrixXmlHashSeed = Cardinal(2166136261);

function LandrixXmlHashBytes(P: PAnsiChar; Len: Integer; Seed: Cardinal): Cardinal;

{ --- Base64 ------------------------------------------------------------- }

{ Appends the base64 encoding (RFC 4648, with padding, no line breaks) of
  Size bytes to Dest. }
procedure LandrixXmlBase64Encode(const Data; Size: Integer; Dest: TLandrixXmlBuffer);

{ Strict xs:base64Binary check of Len bytes at P: RFC 4648 alphabet, XML
  white space (TAB, LF, CR, space) allowed anywhere, padding required and
  only at the end, unused bits of the last group must be zero. Returns
  True and the decoded size, or False and the offset of the first bad byte
  (Len for a truncated group). }
function LandrixXmlValidateBase64Buf(P: PAnsiChar; Len: Integer;
  out DecodedSize: Integer; out BadOffset: Integer): Boolean;

{ Decodes Len bytes at P (checked as above) and appends the bytes to Dest.
  Raises ELandrixXmlError (xecConversion, Offset = position in the input)
  before anything is appended. }
procedure LandrixXmlBase64Decode(P: PAnsiChar; Len: Integer; Dest: TLandrixXmlBuffer);

{ Like LandrixXmlBase64Decode, but writes to Stream in blocks of 48 KB, so
  large attachments are never held twice in memory. The input is checked
  completely before the first byte is written. }
procedure LandrixXmlBase64DecodeToStream(P: PAnsiChar; Len: Integer; Stream: TStream);

{ --- Validation --------------------------------------------------------- }

{ True if S is strictly valid UTF-8. Otherwise BadOffset receives the
  0-based offset of the first invalid sequence; -1 when valid. }
function LandrixXmlValidateUtf8(const S: TLandrixXmlUtf8;
  out BadOffset: Integer): Boolean;
function LandrixXmlValidateUtf8Buf(P: PAnsiChar; Len: Integer;
  out BadOffset: Integer): Boolean;

{ --- Conversion (the only place where string types are converted) ------ }

function LandrixXmlUtf8ToWide(const S: TLandrixXmlUtf8): TLandrixXmlWide;
function LandrixXmlWideToUtf8(const S: TLandrixXmlWide): TLandrixXmlUtf8;
function LandrixXmlUtf8ToString(const S: TLandrixXmlUtf8): string;
function LandrixXmlStringToUtf8(const S: string): TLandrixXmlUtf8;

{ Copies Len bytes to a new TLandrixXmlUtf8 after strict validation. }
function LandrixXmlBufToUtf8(P: PAnsiChar; Len: Integer): TLandrixXmlUtf8;

{ --- Diagnostics -------------------------------------------------------- }

{ Renders UTF-8 text as ASCII for error messages: printable ASCII is kept,
  other code points become U+XXXX, invalid bytes become \xHH. At most
  MaxChars input characters are rendered; longer text ends with '...'. }
function LandrixXmlEscapeForMessage(const S: TLandrixXmlUtf8;
  MaxChars: Integer): string;

implementation

const
  SMaxBufferSize = 'Buffer size limit exceeded';

{ --- ELandrixXmlError --------------------------------------------------- }

constructor ELandrixXmlError.CreateCode(ACode: TLandrixXmlErrorCode;
  const Msg: string);
begin
  inherited Create(Msg);
  FCode := ACode;
end;

constructor ELandrixXmlError.CreateAt(ACode: TLandrixXmlErrorCode;
  const Msg: string; ALine, AColumn: Integer; AOffset: Int64);
var
  Pos: string;
begin
  Pos := '';
  if ALine > 0 then
  begin
    Pos := 'line ' + IntToStr(ALine);
    if AColumn > 0 then
      Pos := Pos + ', column ' + IntToStr(AColumn);
  end;
  if AOffset >= 0 then
  begin
    if Pos <> '' then
      Pos := Pos + ', ';
    Pos := Pos + 'offset ' + IntToStr(AOffset);
  end;
  if Pos <> '' then
    inherited Create(Msg + ' (' + Pos + ')')
  else
    inherited Create(Msg);
  FCode := ACode;
  if ALine > 0 then
    FLine := ALine;
  if AColumn > 0 then
    FColumn := AColumn;
  if AOffset >= 0 then
    FOffsetPlusOne := AOffset + 1;
end;

function ELandrixXmlError.GetOffset: Int64;
begin
  Result := FOffsetPlusOne - 1;
end;

procedure RaiseInvalidArgument(const Msg: string);
begin
  raise ELandrixXmlError.CreateCode(xecInvalidArgument, Msg);
end;

procedure RaiseLimit(const Msg: string);
begin
  raise ELandrixXmlError.CreateCode(xecLimit, Msg);
end;

procedure RaiseInvalidUtf8(Offset: Integer);
begin
  raise ELandrixXmlError.CreateAt(xecInvalidUnicode,
    'Invalid UTF-8 byte sequence', 0, 0, Offset);
end;

procedure RaiseInvalidUtf16(Index: Integer);
begin
  raise ELandrixXmlError.CreateAt(xecInvalidUnicode,
    'Unpaired UTF-16 surrogate', 0, 0, Index);
end;

{ --- Code point primitives --------------------------------------------- }

function LandrixXmlDecodeUtf8(P: PAnsiChar; Len: Integer;
  out CodePoint: Cardinal): Integer;
var
  B0, B1, B2, B3: Cardinal;
begin
  Result := 0;
  CodePoint := 0;
  if Len <= 0 then
    Exit;
  B0 := Ord(P[0]);
  if B0 < $80 then
  begin
    CodePoint := B0;
    Result := 1;
  end
  else if B0 < $C2 then
    { continuation byte or overlong lead C0/C1 }
  else if B0 < $E0 then
  begin
    if Len < 2 then
      Exit;
    B1 := Ord(P[1]);
    if (B1 and $C0) <> $80 then
      Exit;
    CodePoint := ((B0 and $1F) shl 6) or (B1 and $3F);
    Result := 2;
  end
  else if B0 < $F0 then
  begin
    if Len < 3 then
      Exit;
    B1 := Ord(P[1]);
    B2 := Ord(P[2]);
    if ((B1 and $C0) <> $80) or ((B2 and $C0) <> $80) then
      Exit;
    if (B0 = $E0) and (B1 < $A0) then
      Exit; { overlong }
    if (B0 = $ED) and (B1 >= $A0) then
      Exit; { UTF-16 surrogate }
    CodePoint := ((B0 and $0F) shl 12) or ((B1 and $3F) shl 6) or (B2 and $3F);
    Result := 3;
  end
  else if B0 < $F5 then
  begin
    if Len < 4 then
      Exit;
    B1 := Ord(P[1]);
    B2 := Ord(P[2]);
    B3 := Ord(P[3]);
    if ((B1 and $C0) <> $80) or ((B2 and $C0) <> $80) or ((B3 and $C0) <> $80) then
      Exit;
    if (B0 = $F0) and (B1 < $90) then
      Exit; { overlong }
    if (B0 = $F4) and (B1 >= $90) then
      Exit; { above U+10FFFF }
    CodePoint := ((B0 and $07) shl 18) or ((B1 and $3F) shl 12) or
      ((B2 and $3F) shl 6) or (B3 and $3F);
    Result := 4;
  end;
end;

function LandrixXmlEncodeUtf8(CodePoint: Cardinal; Dest: PAnsiChar): Integer;
begin
  if CodePoint < $80 then
  begin
    Dest[0] := AnsiChar(CodePoint);
    Result := 1;
  end
  else if CodePoint < $800 then
  begin
    Dest[0] := AnsiChar($C0 or (CodePoint shr 6));
    Dest[1] := AnsiChar($80 or (CodePoint and $3F));
    Result := 2;
  end
  else if CodePoint < $10000 then
  begin
    if (CodePoint >= $D800) and (CodePoint <= $DFFF) then
    begin
      Result := 0;
      Exit;
    end;
    Dest[0] := AnsiChar($E0 or (CodePoint shr 12));
    Dest[1] := AnsiChar($80 or ((CodePoint shr 6) and $3F));
    Dest[2] := AnsiChar($80 or (CodePoint and $3F));
    Result := 3;
  end
  else if CodePoint <= LandrixXmlMaxCodePoint then
  begin
    Dest[0] := AnsiChar($F0 or (CodePoint shr 18));
    Dest[1] := AnsiChar($80 or ((CodePoint shr 12) and $3F));
    Dest[2] := AnsiChar($80 or ((CodePoint shr 6) and $3F));
    Dest[3] := AnsiChar($80 or (CodePoint and $3F));
    Result := 4;
  end
  else
    Result := 0;
end;

function LandrixXmlIsXmlChar(CodePoint: Cardinal): Boolean;
begin
  if CodePoint < $20 then
    Result := (CodePoint = 9) or (CodePoint = 10) or (CodePoint = 13)
  else if CodePoint <= $D7FF then
    Result := True
  else if CodePoint < $E000 then
    Result := False
  else if CodePoint <= $FFFD then
    Result := True
  else
    Result := (CodePoint >= $10000) and (CodePoint <= LandrixXmlMaxCodePoint);
end;

function LandrixXmlIsNameStartChar(CodePoint: Cardinal): Boolean;
begin
  if CodePoint < $80 then
    Result := ((CodePoint >= Ord('A')) and (CodePoint <= Ord('Z'))) or
      ((CodePoint >= Ord('a')) and (CodePoint <= Ord('z'))) or
      (CodePoint = Ord('_')) or (CodePoint = Ord(':'))
  else
    Result := ((CodePoint >= $C0) and (CodePoint <= $D6)) or
      ((CodePoint >= $D8) and (CodePoint <= $F6)) or
      ((CodePoint >= $F8) and (CodePoint <= $2FF)) or
      ((CodePoint >= $370) and (CodePoint <= $37D)) or
      ((CodePoint >= $37F) and (CodePoint <= $1FFF)) or
      ((CodePoint >= $200C) and (CodePoint <= $200D)) or
      ((CodePoint >= $2070) and (CodePoint <= $218F)) or
      ((CodePoint >= $2C00) and (CodePoint <= $2FEF)) or
      ((CodePoint >= $3001) and (CodePoint <= $D7FF)) or
      ((CodePoint >= $F900) and (CodePoint <= $FDCF)) or
      ((CodePoint >= $FDF0) and (CodePoint <= $FFFD)) or
      ((CodePoint >= $10000) and (CodePoint <= $EFFFF));
end;

function LandrixXmlIsNameChar(CodePoint: Cardinal): Boolean;
begin
  if CodePoint < $80 then
    Result := LandrixXmlIsNameStartChar(CodePoint) or
      ((CodePoint >= Ord('0')) and (CodePoint <= Ord('9'))) or
      (CodePoint = Ord('-')) or (CodePoint = Ord('.'))
  else
    Result := LandrixXmlIsNameStartChar(CodePoint) or (CodePoint = $B7) or
      ((CodePoint >= $300) and (CodePoint <= $36F)) or
      ((CodePoint >= $203F) and (CodePoint <= $2040));
end;

function LandrixXmlCheckName(P: PAnsiChar; Len: Integer): Integer;
var
  I, N: Integer;
  CodePoint: Cardinal;
begin
  Result := 0;
  if Len <= 0 then
    Exit;
  I := 0;
  while I < Len do
  begin
    N := LandrixXmlDecodeUtf8(P + I, Len - I, CodePoint);
    if N = 0 then
    begin
      Result := I;
      Exit;
    end;
    if I = 0 then
    begin
      if not LandrixXmlIsNameStartChar(CodePoint) then
        Exit;
    end
    else if not LandrixXmlIsNameChar(CodePoint) then
    begin
      Result := I;
      Exit;
    end;
    Inc(I, N);
  end;
  Result := -1;
end;

function LandrixXmlHashBytes(P: PAnsiChar; Len: Integer; Seed: Cardinal): Cardinal;
var
  I: Integer;
begin
  Result := Seed;
  for I := 0 to Len - 1 do
    { computed in Int64 and masked: the wrap-around is intended and must not
      trip overflow or range checking in projects compiled with Q+/R+ }
    Result := Cardinal((Int64(Result xor Ord(P[I])) * 16777619) and $FFFFFFFF);
end;

{ --- Base64 ------------------------------------------------------------- }

const
  Base64Chars: array[0..63] of AnsiChar =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

procedure LandrixXmlBase64Encode(const Data; Size: Integer; Dest: TLandrixXmlBuffer);
var
  Src: PAnsiChar;
  Dst: PAnsiChar;
  I, Full, Rest: Integer;
  V: Cardinal;
begin
  if Size < 0 then
    RaiseInvalidArgument('Negative base64 input size');
  if Size = 0 then
    Exit;
  if Size > (MaxInt div 4) * 3 - 3 then
    RaiseLimit('Base64 input too large');
  Src := PAnsiChar(@Data);
  Full := Size div 3;
  Rest := Size - Full * 3;
  if Rest > 0 then
    Dst := Dest.Extend((Full + 1) * 4)
  else
    Dst := Dest.Extend(Full * 4);
  for I := 0 to Full - 1 do
  begin
    V := (Cardinal(Ord(Src[0])) shl 16) or (Cardinal(Ord(Src[1])) shl 8) or
      Cardinal(Ord(Src[2]));
    Dst[0] := Base64Chars[(V shr 18) and 63];
    Dst[1] := Base64Chars[(V shr 12) and 63];
    Dst[2] := Base64Chars[(V shr 6) and 63];
    Dst[3] := Base64Chars[V and 63];
    Inc(Src, 3);
    Inc(Dst, 4);
  end;
  if Rest > 0 then
  begin
    V := Cardinal(Ord(Src[0])) shl 16;
    if Rest = 2 then
      V := V or (Cardinal(Ord(Src[1])) shl 8);
    Dst[0] := Base64Chars[(V shr 18) and 63];
    Dst[1] := Base64Chars[(V shr 12) and 63];
    if Rest = 2 then
      Dst[2] := Base64Chars[(V shr 6) and 63]
    else
      Dst[2] := '=';
    Dst[3] := '=';
  end;
end;

{ Value of a base64 symbol, -1 for anything else. }
function Base64Value(C: AnsiChar): Integer;
begin
  case C of
    'A'..'Z': Result := Ord(C) - Ord('A');
    'a'..'z': Result := Ord(C) - Ord('a') + 26;
    '0'..'9': Result := Ord(C) - Ord('0') + 52;
    '+': Result := 62;
    '/': Result := 63;
  else
    Result := -1;
  end;
end;

function IsBase64Space(C: AnsiChar): Boolean;
begin
  Result := (C = ' ') or (C = #9) or (C = #10) or (C = #13);
end;

function LandrixXmlValidateBase64Buf(P: PAnsiChar; Len: Integer;
  out DecodedSize: Integer; out BadOffset: Integer): Boolean;
var
  I, N, Pad, V, Bits, BitsPos: Integer;
  Ended: Boolean;
begin
  Result := False;
  DecodedSize := 0;
  BadOffset := -1;
  if Len < 0 then
    RaiseInvalidArgument('Negative base64 input length');
  N := 0;          { symbols in the current group of four }
  Pad := 0;        { '=' in the current group }
  Ended := False;  { a padded group was complete: nothing may follow }
  Bits := 0;       { value and position of the last data symbol }
  BitsPos := 0;
  for I := 0 to Len - 1 do
  begin
    if IsBase64Space(P[I]) then
      Continue;
    if Ended then
    begin
      BadOffset := I;
      Exit;
    end;
    if P[I] = '=' then
    begin
      if N < 2 then
      begin
        BadOffset := I;
        Exit;
      end;
      { the unused low bits of the last data symbol must be zero }
      if ((N = 2) and (Bits and 15 <> 0)) or ((N = 3) and (Pad = 0) and (Bits and 3 <> 0)) then
      begin
        BadOffset := BitsPos;
        Exit;
      end;
      Inc(Pad);
    end
    else
    begin
      V := Base64Value(P[I]);
      if (V < 0) or (Pad > 0) then
      begin
        BadOffset := I;
        Exit;
      end;
      Bits := V;
      BitsPos := I;
    end;
    Inc(N);
    if N = 4 then
    begin
      Inc(DecodedSize, 3 - Pad);
      Ended := Pad > 0;
      N := 0;
      Pad := 0;
    end;
  end;
  if N <> 0 then
  begin
    BadOffset := Len;
    DecodedSize := 0;
    Exit;
  end;
  Result := True;
end;

{ Decodes already validated input; output goes to Dest, which is flushed
  to Stream in blocks when Stream is assigned. }
procedure Base64DecodeValid(P: PAnsiChar; Len: Integer; Dest: TLandrixXmlBuffer;
  Stream: TStream);
var
  I, N, Pad: Integer;
  Quad: Cardinal;
  Bytes: array[0..2] of Byte;
begin
  N := 0;
  Pad := 0;
  Quad := 0;
  for I := 0 to Len - 1 do
  begin
    if IsBase64Space(P[I]) then
      Continue;
    Quad := Quad shl 6;
    if P[I] = '=' then
      Inc(Pad)
    else
      Quad := Quad or Cardinal(Base64Value(P[I]));
    Inc(N);
    if N = 4 then
    begin
      Bytes[0] := Byte(Quad shr 16);
      Bytes[1] := Byte(Quad shr 8);
      Bytes[2] := Byte(Quad);
      Dest.Append(PAnsiChar(@Bytes)^, 3 - Pad);
      if (Stream <> nil) and (Dest.Size >= 49152) then
      begin
        Dest.WriteToStream(Stream);
        Dest.Clear;
      end;
      N := 0;
      Pad := 0;
      Quad := 0;
    end;
  end;
  if (Stream <> nil) and (Dest.Size > 0) then
  begin
    Dest.WriteToStream(Stream);
    Dest.Clear;
  end;
end;

procedure RaiseInvalidBase64(Offset: Integer);
begin
  raise ELandrixXmlError.CreateAt(xecConversion, 'Invalid base64 data', 0, 0, Offset);
end;

procedure LandrixXmlBase64Decode(P: PAnsiChar; Len: Integer; Dest: TLandrixXmlBuffer);
var
  Size, Bad: Integer;
begin
  if not LandrixXmlValidateBase64Buf(P, Len, Size, Bad) then
    RaiseInvalidBase64(Bad);
  Dest.Reserve(Dest.Size + Size);
  Base64DecodeValid(P, Len, Dest, nil);
end;

procedure LandrixXmlBase64DecodeToStream(P: PAnsiChar; Len: Integer; Stream: TStream);
var
  Size, Bad: Integer;
  Block: TLandrixXmlBuffer;
begin
  if Stream = nil then
    RaiseInvalidArgument('Stream must not be nil');
  if not LandrixXmlValidateBase64Buf(P, Len, Size, Bad) then
    RaiseInvalidBase64(Bad);
  Block := TLandrixXmlBuffer.Create;
  try
    Base64DecodeValid(P, Len, Block, Stream);
  finally
    Block.Free;
  end;
end;

{ --- Validation --------------------------------------------------------- }

function LandrixXmlValidateUtf8Buf(P: PAnsiChar; Len: Integer;
  out BadOffset: Integer): Boolean;
var
  I, N: Integer;
  CodePoint: Cardinal;
begin
  I := 0;
  while I < Len do
  begin
    if Ord(P[I]) < $80 then
      Inc(I)
    else
    begin
      N := LandrixXmlDecodeUtf8(P + I, Len - I, CodePoint);
      if N = 0 then
      begin
        BadOffset := I;
        Result := False;
        Exit;
      end;
      Inc(I, N);
    end;
  end;
  BadOffset := -1;
  Result := True;
end;

function LandrixXmlValidateUtf8(const S: TLandrixXmlUtf8;
  out BadOffset: Integer): Boolean;
begin
  Result := LandrixXmlValidateUtf8Buf(PAnsiChar(S), Length(S), BadOffset);
end;

{ --- UTF-8 <-> UTF-16 cores ---------------------------------------------- }

{ Converts UTF-8 to UTF-16. With Dest = nil only counts. Returns the number
  of UTF-16 code units, or -1 with BadOffset set on invalid input. }
function Utf8ToUtf16(Src: PAnsiChar; SrcLen: Integer; Dest: PWideChar;
  out BadOffset: Integer): Integer;
var
  I, N, Units: Integer;
  CodePoint: Cardinal;
begin
  I := 0;
  Units := 0;
  BadOffset := -1;
  while I < SrcLen do
  begin
    if Ord(Src[I]) < $80 then
    begin
      if Dest <> nil then
        Dest[Units] := WideChar(Ord(Src[I]));
      Inc(Units);
      Inc(I);
    end
    else
    begin
      N := LandrixXmlDecodeUtf8(Src + I, SrcLen - I, CodePoint);
      if N = 0 then
      begin
        BadOffset := I;
        Result := -1;
        Exit;
      end;
      if CodePoint >= $10000 then
      begin
        if Dest <> nil then
        begin
          Dest[Units] := WideChar($D800 + ((CodePoint - $10000) shr 10));
          Dest[Units + 1] := WideChar($DC00 + ((CodePoint - $10000) and $3FF));
        end;
        Inc(Units, 2);
      end
      else
      begin
        if Dest <> nil then
          Dest[Units] := WideChar(CodePoint);
        Inc(Units);
      end;
      Inc(I, N);
    end;
  end;
  Result := Units;
end;

{ Counts the UTF-8 bytes needed for Src. Returns -1 with BadIndex set on an
  unpaired surrogate. }
function Utf16CountUtf8(Src: PWideChar; SrcLen: Integer;
  out BadIndex: Integer): Int64;
var
  I: Integer;
  U: Cardinal;
begin
  Result := 0;
  BadIndex := -1;
  I := 0;
  while I < SrcLen do
  begin
    U := Ord(Src[I]);
    if U < $80 then
      Inc(Result)
    else if U < $800 then
      Inc(Result, 2)
    else if (U >= $D800) and (U <= $DBFF) then
    begin
      if (I + 1 < SrcLen) and (Ord(Src[I + 1]) >= $DC00) and (Ord(Src[I + 1]) <= $DFFF) then
      begin
        Inc(Result, 4);
        Inc(I);
      end
      else
      begin
        BadIndex := I;
        Result := -1;
        Exit;
      end;
    end
    else if (U >= $DC00) and (U <= $DFFF) then
    begin
      BadIndex := I;
      Result := -1;
      Exit;
    end
    else
      Inc(Result, 3);
    Inc(I);
  end;
end;

{ Converts valid UTF-16 (checked by Utf16CountUtf8) to UTF-8. }
procedure Utf16FillUtf8(Src: PWideChar; SrcLen: Integer; Dest: PAnsiChar);
var
  I, O: Integer;
  U, CodePoint: Cardinal;
begin
  I := 0;
  O := 0;
  while I < SrcLen do
  begin
    U := Ord(Src[I]);
    if U < $80 then
    begin
      Dest[O] := AnsiChar(U);
      Inc(O);
    end
    else
    begin
      if (U >= $D800) and (U <= $DBFF) then
      begin
        CodePoint := $10000 + ((U - $D800) shl 10) + (Cardinal(Ord(Src[I + 1])) - $DC00);
        Inc(I);
      end
      else
        CodePoint := U;
      Inc(O, LandrixXmlEncodeUtf8(CodePoint, Dest + O));
    end;
    Inc(I);
  end;
end;

{ --- Conversion --------------------------------------------------------- }

function Utf8BufToWide(P: PAnsiChar; Len: Integer): TLandrixXmlWide;
var
  Units, BadOffset: Integer;
begin
  Result := '';
  if Len = 0 then
    Exit;
  Units := Utf8ToUtf16(P, Len, nil, BadOffset);
  if Units < 0 then
    RaiseInvalidUtf8(BadOffset);
  SetLength(Result, Units);
  Utf8ToUtf16(P, Len, PWideChar(Result), BadOffset);
end;

function WideBufToUtf8(P: PWideChar; Len: Integer): TLandrixXmlUtf8;
var
  Count: Int64;
  BadIndex: Integer;
begin
  Result := '';
  if Len = 0 then
    Exit;
  Count := Utf16CountUtf8(P, Len, BadIndex);
  if Count < 0 then
    RaiseInvalidUtf16(BadIndex);
  if Count > MaxInt - 1 then
    RaiseLimit('String too long for UTF-8 conversion');
  SetLength(Result, Integer(Count));
  Utf16FillUtf8(P, Len, PAnsiChar(Result));
end;

function LandrixXmlBufToUtf8(P: PAnsiChar; Len: Integer): TLandrixXmlUtf8;
var
  BadOffset: Integer;
begin
  Result := '';
  if Len < 0 then
    RaiseInvalidArgument('Negative length');
  if Len = 0 then
    Exit;
  if not LandrixXmlValidateUtf8Buf(P, Len, BadOffset) then
    RaiseInvalidUtf8(BadOffset);
  SetLength(Result, Len);
  Move(P^, PAnsiChar(Result)^, Len);
end;

function LandrixXmlUtf8ToWide(const S: TLandrixXmlUtf8): TLandrixXmlWide;
begin
  Result := Utf8BufToWide(PAnsiChar(S), Length(S));
end;

function LandrixXmlWideToUtf8(const S: TLandrixXmlWide): TLandrixXmlUtf8;
begin
  Result := WideBufToUtf8(PWideChar(S), Length(S));
end;

{$IFDEF FPC}
{ Code page the RTL uses for S, with CP_ACP resolved. }
function EffectiveCodePage(const S: string): Cardinal;
begin
  Result := StringCodePage(S);
  if Result = CP_ACP then
    Result := DefaultSystemCodePage;
end;
{$ENDIF}

function LandrixXmlUtf8ToString(const S: TLandrixXmlUtf8): string;
{$IFDEF LANDRIXXML_UNICODE}
begin
  Result := Utf8BufToWide(PAnsiChar(S), Length(S));
end;
{$ELSE}
{$IFDEF FPC}
var
  BadOffset: Integer;
begin
  Result := '';
  if Length(S) = 0 then
    Exit;
  if DefaultSystemCodePage = CP_UTF8 then
  begin
    if not LandrixXmlValidateUtf8Buf(PAnsiChar(S), Length(S), BadOffset) then
      RaiseInvalidUtf8(BadOffset);
    SetLength(Result, Length(S));
    Move(PAnsiChar(S)^, PAnsiChar(Result)^, Length(S));
  end
  else
    Result := string(Utf8BufToWide(PAnsiChar(S), Length(S)));
end;
{$ELSE}
begin
  { Delphi 6-2007: the RTL converts to the system code page (lossy). }
  Result := string(Utf8BufToWide(PAnsiChar(S), Length(S)));
end;
{$ENDIF}
{$ENDIF}

function LandrixXmlStringToUtf8(const S: string): TLandrixXmlUtf8;
{$IFDEF LANDRIXXML_UNICODE}
begin
  Result := WideBufToUtf8(PWideChar(S), Length(S));
end;
{$ELSE}
{$IFDEF FPC}
var
  W: TLandrixXmlWide;
begin
  Result := '';
  if Length(S) = 0 then
    Exit;
  if EffectiveCodePage(S) = CP_UTF8 then
    Result := LandrixXmlBufToUtf8(PAnsiChar(S), Length(S))
  else
  begin
    W := TLandrixXmlWide(S);
    Result := WideBufToUtf8(PWideChar(W), Length(W));
  end;
end;
{$ELSE}
var
  W: TLandrixXmlWide;
begin
  { Delphi 6-2007: the RTL converts from the system code page. }
  W := TLandrixXmlWide(S);
  Result := WideBufToUtf8(PWideChar(W), Length(W));
end;
{$ENDIF}
{$ENDIF}

{ --- Diagnostics -------------------------------------------------------- }

function LandrixXmlEscapeForMessage(const S: TLandrixXmlUtf8;
  MaxChars: Integer): string;
var
  P: PAnsiChar;
  I, Len, N, Chars: Integer;
  CodePoint: Cardinal;
begin
  Result := '';
  P := PAnsiChar(S);
  Len := Length(S);
  I := 0;
  Chars := 0;
  while I < Len do
  begin
    if Chars >= MaxChars then
    begin
      Result := Result + '...';
      Exit;
    end;
    N := LandrixXmlDecodeUtf8(P + I, Len - I, CodePoint);
    if N = 0 then
    begin
      Result := Result + '\x' + IntToHex(Ord(P[I]), 2);
      N := 1;
    end
    else if (CodePoint >= $20) and (CodePoint <= $7E) then
      Result := Result + Char(CodePoint)
    else
      Result := Result + 'U+' + IntToHex(CodePoint, 4);
    Inc(I, N);
    Inc(Chars);
  end;
end;

{ --- TLandrixXmlBuffer ---------------------------------------------------- }

destructor TLandrixXmlBuffer.Destroy;
begin
  if FData <> nil then
    FreeMem(FData);
  inherited Destroy;
end;

procedure TLandrixXmlBuffer.Clear;
begin
  FSize := 0;
  if FData <> nil then
    FData[0] := #0;
end;

procedure TLandrixXmlBuffer.Reserve(MinCapacity: Integer);
var
  NewCapacity: Integer;
begin
  if MinCapacity < 0 then
    RaiseInvalidArgument('Negative capacity');
  if MinCapacity <= FCapacity then
    Exit;
  if MinCapacity >= MaxInt then
    RaiseLimit(SMaxBufferSize);
  if FCapacity >= (MaxInt - 1) div 2 then
    NewCapacity := MaxInt - 1
  else
    NewCapacity := FCapacity * 2;
  if NewCapacity < 256 then
    NewCapacity := 256;
  if NewCapacity < MinCapacity then
    NewCapacity := MinCapacity;
  { one extra byte for the #0 sentinel }
  ReallocMem(FData, NewCapacity + 1);
  FCapacity := NewCapacity;
  FData[FSize] := #0;
end;

procedure TLandrixXmlBuffer.Truncate(NewSize: Integer);
begin
  if (NewSize < 0) or (NewSize > FSize) then
    RaiseInvalidArgument('Truncate size out of range');
  FSize := NewSize;
  if FData <> nil then
    FData[FSize] := #0;
end;

procedure TLandrixXmlBuffer.Append(const Data; Count: Integer);
var
  Src: PAnsiChar;
  Delta: Integer;
begin
  if Count < 0 then
    RaiseInvalidArgument('Negative count');
  if Count = 0 then
    Exit;
  if Count > MaxInt - 1 - FSize then
    RaiseLimit(SMaxBufferSize);
  Src := PAnsiChar(@Data);
  if FSize + Count > FCapacity then
  begin
    if (FData <> nil) and (Src >= FData) and (Src <= FData + FCapacity) then
    begin
      { source lies inside our own memory, which is about to move }
      Delta := Integer(Src - FData);
      Reserve(FSize + Count);
      Src := FData + Delta;
    end
    else
      Reserve(FSize + Count);
  end;
  Move(Src^, FData[FSize], Count);
  Inc(FSize, Count);
  FData[FSize] := #0;
end;

function TLandrixXmlBuffer.Extend(Count: Integer): PAnsiChar;
begin
  if Count < 0 then
    RaiseInvalidArgument('Negative count');
  if Count = 0 then
  begin
    Result := nil;
    Exit;
  end;
  if Count > MaxInt - 1 - FSize then
    RaiseLimit(SMaxBufferSize);
  if FSize + Count > FCapacity then
    Reserve(FSize + Count);
  Result := FData + FSize;
  Inc(FSize, Count);
  FData[FSize] := #0;
end;

procedure TLandrixXmlBuffer.AppendByte(B: Byte);
begin
  if FSize >= FCapacity then
    Reserve(FSize + 1);
  FData[FSize] := AnsiChar(B);
  Inc(FSize);
  FData[FSize] := #0;
end;

procedure TLandrixXmlBuffer.AppendUtf8(const S: TLandrixXmlUtf8);
begin
  if Length(S) > 0 then
    Append(PAnsiChar(S)^, Length(S));
end;

procedure TLandrixXmlBuffer.AppendAscii(const S: AnsiString);
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    if Ord(S[I]) >= $80 then
      RaiseInvalidArgument('AppendAscii: non-ASCII byte');
  if Length(S) > 0 then
    Append(PAnsiChar(S)^, Length(S));
end;

procedure TLandrixXmlBuffer.AppendCodePoint(CodePoint: Cardinal);
var
  Bytes: array[0..3] of AnsiChar;
  N: Integer;
begin
  N := LandrixXmlEncodeUtf8(CodePoint, @Bytes[0]);
  if N = 0 then
    raise ELandrixXmlError.CreateCode(xecInvalidUnicode,
      'Invalid code point U+' + IntToHex(CodePoint, 4));
  Append(Bytes[0], N);
end;

function TLandrixXmlBuffer.AsUtf8: TLandrixXmlUtf8;
begin
  Result := '';
  if FSize > 0 then
  begin
    SetLength(Result, FSize);
    Move(FData^, PAnsiChar(Result)^, FSize);
  end;
end;

procedure TLandrixXmlBuffer.WriteToStream(Stream: TStream);
begin
  if FSize > 0 then
    Stream.WriteBuffer(FData^, FSize);
end;

end.
