{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Input layer: detects the encoding of an XML document (byte order mark and
  XML declaration), converts it to UTF-8 and maps positions back to the
  original bytes.

  Supported: UTF-8, UTF-16 LE/BE, ISO-8859-1, Windows-1252, ISO-8859-15 and
  US-ASCII. Everything else (UTF-32, EBCDIC, other code pages) is rejected
  with xecEncoding. The rules (strict by default, opt-in repair) are listed
  with TLandrixXmlInput below. }

unit LandrixXmlEncoding;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  Classes,
  LandrixXmlBase;

type
  { Source encodings. Append-only: never reorder or remove values. }
  TLandrixXmlEncoding = (
    xenUnknown,
    xenUtf8,
    xenUtf16LE,
    xenUtf16BE,
    xenIso88591,
    xenWindows1252,
    xenAscii,
    xenIso885915
  );

  { Result of LandrixXmlScanDeclaration. All offsets are relative to the
    scanned memory; values are given without their quotes. A length of 0
    means the pseudo-attribute is absent (version is always present). }
  TLandrixXmlDeclaration = record
    Present: Boolean;
    VersionStart: Integer;
    VersionLength: Integer;
    EncodingStart: Integer;
    EncodingLength: Integer;
    StandaloneStart: Integer;
    StandaloneLength: Integer;
    { offset directly after '?>' }
    EndOffset: Integer;
  end;

  { Normalized input of the parser.

    Rules:
    - A UTF-8, UTF-16 LE or UTF-16 BE byte order mark selects the encoding;
      one BOM is removed. UTF-32/UCS-4 and EBCDIC signatures are rejected.
    - Without BOM the XML declaration decides; no declaration means UTF-8.
      UTF-16 without BOM is accepted only when declared as UTF-16LE or
      UTF-16BE matching the byte order.
    - A declaration that contradicts the BOM or the detected byte layout is
      an error (xecEncoding).
    - Malformed UTF-8 or UTF-16 raises xecInvalidUnicode, a NUL character
      raises xecInvalidChar, a byte >= $80 in US-ASCII raises xecEncoding.
    - ISO-8859-1 is strict (bytes $80-$9F are U+0080-U+009F). Windows-1252
      maps its undefined bytes $81, $8D, $8F, $90, $9D to U+0081 etc.

    Opt-in repair for faulty files (default off):
    - FallbackEncoding: single-byte encoding used when there is no BOM, the
      declaration says UTF-8 or nothing, and the bytes are not valid UTF-8.
    - Latin1AsWindows1252: decode declared ISO-8859-1 as Windows-1252.
    SourceEncoding always reports the decoder actually used and
    DeclaredEncoding the declaration as written, so a repair is visible.

    Error offsets refer to the original bytes (BOM included). A failed load
    leaves the input empty. }
  TLandrixXmlInput = class
  private
    FRaw: TLandrixXmlBuffer;
    FOut: TLandrixXmlBuffer;
    FData: PAnsiChar;
    FSize: Integer;
    FBomSize: Integer;
    FOriginalSize: Int64;
    FSourceEncoding: TLandrixXmlEncoding;
    FDeclaredEncoding: TLandrixXmlUtf8;
    FHadBom: Boolean;
    FFallbackEncoding: TLandrixXmlEncoding;
    FLatin1AsWindows1252: Boolean;
    { start of the declared encoding name (for error positions) }
    FDeclBody: PAnsiChar;
    FDeclStart: Integer;
    procedure RaiseDeclError(const Msg: string);
    procedure SetFallbackEncoding(Value: TLandrixXmlEncoding);
    procedure ResetState;
    procedure Decode(Authoritative: Boolean);
    procedure DecodeUtf16(BigEndian: Boolean);
    procedure DecodeAsciiCompatible(Authoritative: Boolean);
    procedure UseInPlaceUtf8(Body: PAnsiChar; Len: Integer);
    procedure ConvertSingleByte(Src: PAnsiChar; Len: Integer;
      Encoding: TLandrixXmlEncoding);
    procedure ReadDeclaration(Body: PAnsiChar; Len: Integer;
      out Decl: TLandrixXmlDeclaration);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    { Reads from the current position to the end of the stream. }
    procedure LoadFromStream(Stream: TStream);
    procedure LoadFromFile(const FileName: string);
    { Copies Size bytes from Data. }
    procedure LoadFromBuffer(const Data; Size: Integer);
    { The string is taken as UTF-8 whatever the declaration says; a declared
      encoding is only recorded in DeclaredEncoding. }
    procedure LoadFromUtf8(const S: TLandrixXmlUtf8);
    { Maps a byte offset in Data to a byte offset in the original input.
      Offsets beyond Size are clamped; negative offsets yield -1. }
    function OriginalOffset(Utf8Offset: Integer): Int64;
    { Normalized UTF-8, never nil, always followed by a #0 byte. }
    property Data: PAnsiChar read FData;
    property Size: Integer read FSize;
    property SourceEncoding: TLandrixXmlEncoding read FSourceEncoding;
    property DeclaredEncoding: TLandrixXmlUtf8 read FDeclaredEncoding;
    property HadBom: Boolean read FHadBom;
    property OriginalSize: Int64 read FOriginalSize;
    property FallbackEncoding: TLandrixXmlEncoding read FFallbackEncoding
      write SetFallbackEncoding;
    property Latin1AsWindows1252: Boolean read FLatin1AsWindows1252
      write FLatin1AsWindows1252;
  end;

{ Scans an XML declaration at the start of P (ASCII-compatible bytes):
    '<?xml' VersionInfo EncodingDecl? SDDecl? S? '?>'
  Returns True if there is no declaration (Decl.Present = False) or if it
  is well-formed. Returns False with ErrorOffset set if it is malformed.
  '<?xml-stylesheet' and other processing instructions are not a
  declaration. }
function LandrixXmlScanDeclaration(P: PAnsiChar; Len: Integer;
  out Decl: TLandrixXmlDeclaration; out ErrorOffset: Integer): Boolean;

{ Canonical name, e.g. 'UTF-8', 'UTF-16LE', 'windows-1252'. }
function LandrixXmlEncodingName(Encoding: TLandrixXmlEncoding): string;

implementation

type
  TEncodingLabel = (elNone, elUnknown, elUtf8, elUtf16, elUtf16LE,
    elUtf16BE, elLatin1, elCp1252, elAscii, elLatin9);

const
  ZeroByte: AnsiChar = #0;

  { Windows-1252 bytes $80-$9F; undefined bytes map to the C1 control. }
  Cp1252High: array[$80..$9F] of Word = (
    $20AC, $0081, $201A, $0192, $201E, $2026, $2020, $2021,
    $02C6, $2030, $0160, $2039, $0152, $008D, $017D, $008F,
    $0090, $2018, $2019, $201C, $201D, $2022, $2013, $2014,
    $02DC, $2122, $0161, $203A, $0153, $009D, $017E, $0178);

{ --- errors ----------------------------------------------------------------- }

procedure RaiseAt(Code: TLandrixXmlErrorCode; const Msg: string;
  Line, Column: Integer; Offset: Int64);
begin
  raise ELandrixXmlError.CreateAt(Code, Msg, Line, Column, Offset);
end;

{ Line and column of the position after Len bytes of valid UTF-8. CR LF,
  CR and LF each end a line. }
procedure LineColumnUtf8(P: PAnsiChar; Len: Integer; out Line, Column: Integer);
var
  I: Integer;
begin
  Line := 1;
  Column := 1;
  I := 0;
  while I < Len do
  begin
    if P[I] = #13 then
    begin
      Inc(Line);
      Column := 1;
      if (I + 1 < Len) and (P[I + 1] = #10) then
        Inc(I);
    end
    else if P[I] = #10 then
    begin
      Inc(Line);
      Column := 1;
    end
    else if (Ord(P[I]) and $C0) <> $80 then
      Inc(Column);
    Inc(I);
  end;
  { the loop counted the lead byte of each character; Column now points
    at the character after the prefix }
end;

{ Same for single-byte encodings: every byte is one character. }
procedure LineColumnBytes(P: PAnsiChar; Len: Integer; out Line, Column: Integer);
var
  I: Integer;
begin
  Line := 1;
  Column := 1;
  I := 0;
  while I < Len do
  begin
    if P[I] = #13 then
    begin
      Inc(Line);
      Column := 1;
      if (I + 1 < Len) and (P[I + 1] = #10) then
        Inc(I);
    end
    else if P[I] = #10 then
    begin
      Inc(Line);
      Column := 1;
    end
    else
      Inc(Column);
    Inc(I);
  end;
end;

function ReadUnit16(P: PAnsiChar; BigEndian: Boolean): Cardinal;
begin
  if BigEndian then
    Result := (Cardinal(Ord(P[0])) shl 8) or Cardinal(Ord(P[1]))
  else
    Result := (Cardinal(Ord(P[1])) shl 8) or Cardinal(Ord(P[0]));
end;

{ Same for UTF-16 code units: a surrogate pair is one character. }
procedure LineColumnUtf16(P: PAnsiChar; Units: Integer; BigEndian: Boolean;
  out Line, Column: Integer);
var
  I: Integer;
  U: Cardinal;
begin
  Line := 1;
  Column := 1;
  I := 0;
  while I < Units do
  begin
    U := ReadUnit16(P + 2 * I, BigEndian);
    if U = 13 then
    begin
      Inc(Line);
      Column := 1;
      if (I + 1 < Units) and (ReadUnit16(P + 2 * (I + 1), BigEndian) = 10) then
        Inc(I);
    end
    else if U = 10 then
    begin
      Inc(Line);
      Column := 1;
    end
    else if (U < $DC00) or (U > $DFFF) then
      Inc(Column);
    Inc(I);
  end;
end;

{ --- names ----------------------------------------------------------------- }

function UpperAscii(P: PAnsiChar; Len: Integer): AnsiString;
var
  I: Integer;
begin
  Result := '';
  SetLength(Result, Len);
  for I := 0 to Len - 1 do
    if (P[I] >= 'a') and (P[I] <= 'z') then
      Result[I + 1] := AnsiChar(Ord(P[I]) - 32)
    else
      Result[I + 1] := P[I];
end;

function LabelFromName(P: PAnsiChar; Len: Integer): TEncodingLabel;
var
  N: AnsiString;
begin
  if Len = 0 then
  begin
    Result := elNone;
    Exit;
  end;
  N := UpperAscii(P, Len);
  if (N = 'UTF-8') or (N = 'UTF8') then
    Result := elUtf8
  else if N = 'UTF-16' then
    Result := elUtf16
  else if N = 'UTF-16LE' then
    Result := elUtf16LE
  else if N = 'UTF-16BE' then
    Result := elUtf16BE
  else if (N = 'ISO-8859-1') or (N = 'ISO_8859-1') or (N = 'ISO8859-1') or
    (N = 'LATIN1') or (N = 'L1') or (N = 'CP819') or (N = 'IBM819') or
    (N = 'ISO-IR-100') or (N = 'CSISOLATIN1') then
    Result := elLatin1
  else if (N = 'WINDOWS-1252') or (N = 'CP1252') then
    Result := elCp1252
  else if (N = 'US-ASCII') or (N = 'ASCII') then
    Result := elAscii
  else if (N = 'ISO-8859-15') or (N = 'ISO_8859-15') or (N = 'ISO8859-15') or
    (N = 'LATIN9') or (N = 'LATIN-9') or (N = 'L9') then
    Result := elLatin9
  else
    Result := elUnknown;
end;

function LandrixXmlEncodingName(Encoding: TLandrixXmlEncoding): string;
begin
  case Encoding of
    xenUtf8: Result := 'UTF-8';
    xenUtf16LE: Result := 'UTF-16LE';
    xenUtf16BE: Result := 'UTF-16BE';
    xenIso88591: Result := 'ISO-8859-1';
    xenWindows1252: Result := 'windows-1252';
    xenAscii: Result := 'US-ASCII';
    xenIso885915: Result := 'ISO-8859-15';
  else
    Result := 'unknown';
  end;
end;

function SingleByteCodePoint(Encoding: TLandrixXmlEncoding; B: Byte): Cardinal;
begin
  Result := B;
  if B < $80 then
    Exit;
  case Encoding of
    xenWindows1252:
      if B <= $9F then
        Result := Cp1252High[B];
    xenIso885915:
      case B of
        $A4: Result := $20AC;
        $A6: Result := $0160;
        $A8: Result := $0161;
        $B4: Result := $017D;
        $B8: Result := $017E;
        $BC: Result := $0152;
        $BD: Result := $0153;
        $BE: Result := $0178;
      end;
  else
    { ISO-8859-1: byte value = code point }
  end;
end;

{ --- declaration scanner ---------------------------------------------------- }

function IsSpace(C: AnsiChar): Boolean;
begin
  Result := (C = ' ') or (C = #9) or (C = #10) or (C = #13);
end;

function IsAsciiLetter(C: AnsiChar): Boolean;
begin
  Result := ((C >= 'a') and (C <= 'z')) or ((C >= 'A') and (C <= 'Z'));
end;

function IsAsciiDigit(C: AnsiChar): Boolean;
begin
  Result := (C >= '0') and (C <= '9');
end;

function MatchAt(P: PAnsiChar; Len, I: Integer; const S: AnsiString): Boolean;
var
  K: Integer;
begin
  Result := I + Length(S) <= Len;
  K := 1;
  while Result and (K <= Length(S)) do
  begin
    Result := P[I + K - 1] = S[K];
    Inc(K);
  end;
end;

function LandrixXmlScanDeclaration(P: PAnsiChar; Len: Integer;
  out Decl: TLandrixXmlDeclaration; out ErrorOffset: Integer): Boolean;
var
  I, Start, NameStart, Order: Integer;
  Name: AnsiString;
  Quote: AnsiChar;
  HadSpace: Boolean;

  function Fail(At: Integer): Boolean;
  begin
    ErrorOffset := At;
    Result := False;
  end;

begin
  Decl.Present := False;
  Decl.VersionStart := 0;
  Decl.VersionLength := 0;
  Decl.EncodingStart := 0;
  Decl.EncodingLength := 0;
  Decl.StandaloneStart := 0;
  Decl.StandaloneLength := 0;
  Decl.EndOffset := 0;
  ErrorOffset := -1;
  Result := True;

  { '<?xml' followed by white space or '?' starts a declaration; any other
    character (e.g. '<?xml-stylesheet') makes it a processing instruction }
  if not MatchAt(P, Len, 0, '<?xml') then
    Exit;
  if (Len > 5) and not IsSpace(P[5]) and (P[5] <> '?') then
    Exit;
  Decl.Present := True;
  I := 5;
  Order := 0; { 0 = expect version, 1 = encoding allowed, 2 = standalone allowed, 3 = none }
  while True do
  begin
    HadSpace := False;
    while (I < Len) and IsSpace(P[I]) do
    begin
      Inc(I);
      HadSpace := True;
    end;
    if I >= Len then
    begin
      Result := Fail(I);
      Exit;
    end;
    if P[I] = '?' then
    begin
      if Order = 0 then
      begin
        Result := Fail(I); { version is required }
        Exit;
      end;
      if (I + 1 < Len) and (P[I + 1] = '>') then
      begin
        Decl.EndOffset := I + 2;
        Exit;
      end;
      Result := Fail(I);
      Exit;
    end;
    if not HadSpace then
    begin
      Result := Fail(I);
      Exit;
    end;
    { pseudo-attribute name }
    NameStart := I;
    while (I < Len) and IsAsciiLetter(P[I]) do
      Inc(I);
    SetString(Name, P + NameStart, I - NameStart);
    if (Name = 'version') and (Order = 0) then
      Order := 1
    else if (Name = 'encoding') and (Order = 1) then
      Order := 2
    else if (Name = 'standalone') and (Order >= 1) and (Order <= 2) then
      Order := 3
    else
    begin
      Result := Fail(NameStart);
      Exit;
    end;
    { Eq ::= S? '=' S? }
    while (I < Len) and IsSpace(P[I]) do
      Inc(I);
    if (I >= Len) or (P[I] <> '=') then
    begin
      Result := Fail(I);
      Exit;
    end;
    Inc(I);
    while (I < Len) and IsSpace(P[I]) do
      Inc(I);
    if (I >= Len) or ((P[I] <> '"') and (P[I] <> '''')) then
    begin
      Result := Fail(I);
      Exit;
    end;
    Quote := P[I];
    Inc(I);
    Start := I;
    while (I < Len) and (P[I] <> Quote) do
      Inc(I);
    if I >= Len then
    begin
      Result := Fail(Start - 1);
      Exit;
    end;
    { validate the value }
    case Order of
      1:
        begin
          { VersionNum ::= '1.' [0-9]+ }
          if (I - Start < 3) or (P[Start] <> '1') or (P[Start + 1] <> '.') then
          begin
            Result := Fail(Start);
            Exit;
          end;
          for NameStart := Start + 2 to I - 1 do
            if not IsAsciiDigit(P[NameStart]) then
            begin
              Result := Fail(NameStart);
              Exit;
            end;
          Decl.VersionStart := Start;
          Decl.VersionLength := I - Start;
        end;
      2:
        begin
          { EncName ::= [A-Za-z] ([A-Za-z0-9._] | '-')* }
          if (I = Start) or not IsAsciiLetter(P[Start]) then
          begin
            Result := Fail(Start);
            Exit;
          end;
          for NameStart := Start + 1 to I - 1 do
            if not (IsAsciiLetter(P[NameStart]) or IsAsciiDigit(P[NameStart]) or
              (P[NameStart] = '.') or (P[NameStart] = '_') or (P[NameStart] = '-')) then
            begin
              Result := Fail(NameStart);
              Exit;
            end;
          Decl.EncodingStart := Start;
          Decl.EncodingLength := I - Start;
        end;
      3:
        begin
          if not (((I - Start = 3) and MatchAt(P, Len, Start, 'yes')) or
            ((I - Start = 2) and MatchAt(P, Len, Start, 'no'))) then
          begin
            Result := Fail(Start);
            Exit;
          end;
          Decl.StandaloneStart := Start;
          Decl.StandaloneLength := I - Start;
        end;
    end;
    Inc(I); { closing quote }
  end;
end;

{ --- TLandrixXmlInput -------------------------------------------------------- }

constructor TLandrixXmlInput.Create;
begin
  inherited Create;
  FRaw := TLandrixXmlBuffer.Create;
  FOut := TLandrixXmlBuffer.Create;
  ResetState;
end;

destructor TLandrixXmlInput.Destroy;
begin
  FOut.Free;
  FRaw.Free;
  inherited Destroy;
end;

procedure TLandrixXmlInput.ResetState;
begin
  FData := @ZeroByte;
  FSize := 0;
  FBomSize := 0;
  FOriginalSize := 0;
  FSourceEncoding := xenUnknown;
  FDeclaredEncoding := '';
  FHadBom := False;
end;

procedure TLandrixXmlInput.Clear;
begin
  FRaw.Clear;
  FOut.Clear;
  ResetState;
end;

procedure TLandrixXmlInput.SetFallbackEncoding(Value: TLandrixXmlEncoding);
begin
  if not (Value in [xenUnknown, xenIso88591, xenWindows1252, xenIso885915]) then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument,
      'FallbackEncoding must be a single-byte encoding or xenUnknown');
  FFallbackEncoding := Value;
end;

procedure TLandrixXmlInput.LoadFromStream(Stream: TStream);
const
  ChunkSize = 65536;
var
  P: PAnsiChar;
  Got: Integer;
  Remaining: Int64;
begin
  Clear;
  try
    try
      Remaining := Stream.Size - Stream.Position;
    except
      { non-seekable stream: read without a size hint }
      Remaining := 0;
    end;
    if (Remaining > 0) and (Remaining < MaxInt - ChunkSize - 1) then
      FRaw.Reserve(Integer(Remaining) + ChunkSize);
    repeat
      P := FRaw.Extend(ChunkSize);
      Got := Stream.Read(P^, ChunkSize);
      if Got < 0 then
        Got := 0;
      FRaw.Truncate(FRaw.Size - ChunkSize + Got);
    until Got = 0;
    Decode(False);
  except
    Clear;
    raise;
  end;
end;

procedure TLandrixXmlInput.LoadFromFile(const FileName: string);
var
  Stream: TFileStream;
begin
  Clear; { also when the file cannot be opened }
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    LoadFromStream(Stream);
  finally
    Stream.Free;
  end;
end;

procedure TLandrixXmlInput.LoadFromBuffer(const Data; Size: Integer);
var
  NewRaw: TLandrixXmlBuffer;
  Src: PAnsiChar;
begin
  Src := PAnsiChar(@Data);
  if Size < 0 then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'Negative size');
  { Data may point into our own memory (e.g. Self.Data), so copy it into a
    fresh buffer before the old ones are cleared }
  NewRaw := TLandrixXmlBuffer.Create;
  try
    NewRaw.Append(Src^, Size);
  except
    NewRaw.Free;
    raise;
  end;
  FRaw.Free;
  FRaw := NewRaw;
  try
    FOut.Clear;
    ResetState;
    Decode(False);
  except
    Clear;
    raise;
  end;
end;

procedure TLandrixXmlInput.LoadFromUtf8(const S: TLandrixXmlUtf8);
begin
  Clear;
  try
    FRaw.AppendUtf8(S);
    Decode(True);
  except
    Clear;
    raise;
  end;
end;

procedure TLandrixXmlInput.Decode(Authoritative: Boolean);
var
  P: PAnsiChar;
  N: Integer;

  function Starts(B0, B1, B2, B3: Integer; Count: Integer): Boolean;
  begin
    Result := N >= Count;
    if Result then
      Result := (Ord(P[0]) = B0) and (Ord(P[1]) = B1);
    if Result and (Count > 2) then
      Result := Ord(P[2]) = B2;
    if Result and (Count > 3) then
      Result := Ord(P[3]) = B3;
  end;

begin
  P := FRaw.Data;
  N := FRaw.Size;
  FOriginalSize := N;
  if N = 0 then
    Exit;
  if not Authoritative then
  begin
    if Starts($00, $00, $FE, $FF, 4) or Starts($FF, $FE, $00, $00, 4) or
      Starts($00, $00, $FF, $FE, 4) or Starts($FE, $FF, $00, $00, 4) or
      Starts($00, $00, $00, $3C, 4) or Starts($3C, $00, $00, $00, 4) or
      Starts($00, $00, $3C, $00, 4) or Starts($00, $3C, $00, $00, 4) then
      RaiseAt(xecEncoding, 'UTF-32/UCS-4 input is not supported', 0, 0, 0);
    if Starts($4C, $6F, $A7, $94, 4) then
      RaiseAt(xecEncoding, 'EBCDIC input is not supported', 0, 0, 0);
    if Starts($FE, $FF, 0, 0, 2) then
    begin
      FBomSize := 2;
      FHadBom := True;
      DecodeUtf16(True);
      Exit;
    end;
    if Starts($FF, $FE, 0, 0, 2) then
    begin
      FBomSize := 2;
      FHadBom := True;
      DecodeUtf16(False);
      Exit;
    end;
    { UTF-16-like layout (ASCII character, zero byte) without '<?' and BOM:
      say so instead of reporting a NUL character }
    if (N >= 4) and (((P[0] <> #0) and (P[1] = #0) and (P[2] <> #0) and (P[3] = #0)) or
      ((P[0] = #0) and (P[1] <> #0) and (P[2] = #0) and (P[3] <> #0))) and
      not Starts($00, $3C, $00, $3F, 4) and not Starts($3C, $00, $3F, $00, 4) then
      RaiseAt(xecEncoding, 'UTF-16 input without byte order mark', 0, 0, 0);
    if Starts($00, $3C, $00, $3F, 4) then
    begin
      DecodeUtf16(True);
      Exit;
    end;
    if Starts($3C, $00, $3F, $00, 4) then
    begin
      DecodeUtf16(False);
      Exit;
    end;
  end;
  if Starts($EF, $BB, $BF, 0, 3) then
  begin
    FBomSize := 3;
    FHadBom := True;
  end;
  DecodeAsciiCompatible(Authoritative);
end;

procedure TLandrixXmlInput.ReadDeclaration(Body: PAnsiChar; Len: Integer;
  out Decl: TLandrixXmlDeclaration);
var
  ErrorOffset, Line, Column: Integer;
  Offset: Int64;
begin
  if not LandrixXmlScanDeclaration(Body, Len, Decl, ErrorOffset) then
  begin
    { for UTF-16 Body is the converted UTF-8 (FData); otherwise Body is the
      raw input, and the declaration is ASCII, so bytes = characters }
    LineColumnUtf8(Body, ErrorOffset, Line, Column);
    if FSourceEncoding in [xenUtf16LE, xenUtf16BE] then
      Offset := OriginalOffset(ErrorOffset)
    else
      Offset := FBomSize + Int64(ErrorOffset);
    RaiseAt(xecSyntax, 'Malformed XML declaration', Line, Column, Offset);
  end;
  if Decl.EncodingLength > 0 then
    FDeclaredEncoding := LandrixXmlBufToUtf8(Body + Decl.EncodingStart,
      Decl.EncodingLength);
  FDeclBody := Body;
  FDeclStart := Decl.EncodingStart;
end;

{ Raises xecEncoding at the declared encoding name (or at the start of the
  document when there is none). }
procedure TLandrixXmlInput.RaiseDeclError(const Msg: string);
var
  Line, Column: Integer;
  Offset: Int64;
begin
  LineColumnUtf8(FDeclBody, FDeclStart, Line, Column);
  if FSourceEncoding in [xenUtf16LE, xenUtf16BE] then
    Offset := OriginalOffset(FDeclStart)
  else
    Offset := FBomSize + Int64(FDeclStart);
  RaiseAt(xecEncoding, Msg, Line, Column, Offset);
end;

procedure TLandrixXmlInput.DecodeUtf16(BigEndian: Boolean);
var
  Src: PAnsiChar;
  Units, I, Line, Column: Integer;
  U, U2, CodePoint: Cardinal;
  Total: Int64;
  Dest: PAnsiChar;
  O: Integer;
  Decl: TLandrixXmlDeclaration;
  Lbl: TEncodingLabel;
  Name: string;
begin
  if BigEndian then
    FSourceEncoding := xenUtf16BE
  else
    FSourceEncoding := xenUtf16LE;
  Src := FRaw.Data + FBomSize;
  if Odd(FRaw.Size - FBomSize) then
    RaiseAt(xecEncoding, 'Odd number of bytes in UTF-16 input', 0, 0,
      Int64(FRaw.Size) - 1);
  Units := (FRaw.Size - FBomSize) div 2;

  { pass 1: validate and count UTF-8 bytes }
  Total := 0;
  I := 0;
  while I < Units do
  begin
    U := ReadUnit16(Src + 2 * I, BigEndian);
    if U = 0 then
    begin
      LineColumnUtf16(Src, I, BigEndian, Line, Column);
      RaiseAt(xecInvalidChar, 'NUL character in input', Line, Column,
        FBomSize + 2 * Int64(I));
    end;
    if U < $80 then
      Inc(Total)
    else if U < $800 then
      Inc(Total, 2)
    else if (U >= $D800) and (U <= $DBFF) then
    begin
      if I + 1 < Units then
        U2 := ReadUnit16(Src + 2 * (I + 1), BigEndian)
      else
        U2 := 0;
      if (U2 < $DC00) or (U2 > $DFFF) then
      begin
        LineColumnUtf16(Src, I, BigEndian, Line, Column);
        RaiseAt(xecInvalidUnicode, 'Unpaired UTF-16 surrogate', Line, Column,
          FBomSize + 2 * Int64(I));
      end;
      Inc(Total, 4);
      Inc(I);
    end
    else if (U >= $DC00) and (U <= $DFFF) then
    begin
      LineColumnUtf16(Src, I, BigEndian, Line, Column);
      RaiseAt(xecInvalidUnicode, 'Unpaired UTF-16 surrogate', Line, Column,
        FBomSize + 2 * Int64(I));
    end
    else
      Inc(Total, 3);
    Inc(I);
  end;
  if Total > MaxInt - 1 then
    RaiseAt(xecLimit, 'Input too large', 0, 0, -1);

  { pass 2: convert }
  FOut.Clear;
  Dest := FOut.Extend(Integer(Total));
  O := 0;
  I := 0;
  while I < Units do
  begin
    U := ReadUnit16(Src + 2 * I, BigEndian);
    if U < $80 then
    begin
      Dest[O] := AnsiChar(U);
      Inc(O);
    end
    else
    begin
      if (U >= $D800) and (U <= $DBFF) then
      begin
        CodePoint := $10000 + ((U - $D800) shl 10) +
          (ReadUnit16(Src + 2 * (I + 1), BigEndian) - $DC00);
        Inc(I);
      end
      else
        CodePoint := U;
      Inc(O, LandrixXmlEncodeUtf8(CodePoint, Dest + O));
    end;
    Inc(I);
  end;
  FData := FOut.Data;
  if FData = nil then
    FData := @ZeroByte;
  FSize := FOut.Size;

  { the declaration must agree with the byte layout }
  ReadDeclaration(FData, FSize, Decl);
  Lbl := LabelFromName(FData + Decl.EncodingStart, Decl.EncodingLength);
  Name := LandrixXmlEscapeForMessage(FDeclaredEncoding, 40);
  if Lbl = elUnknown then
    RaiseDeclError('Unsupported encoding "' + Name + '"');
  if FHadBom then
  begin
    if not ((Lbl = elNone) or (Lbl = elUtf16) or
      ((Lbl = elUtf16LE) and not BigEndian) or ((Lbl = elUtf16BE) and BigEndian)) then
      RaiseDeclError('Byte order mark indicates ' +
        LandrixXmlEncodingName(FSourceEncoding) + ', declaration says "' +
        Name + '"');
  end
  else
  begin
    if Lbl = elNone then
      RaiseDeclError(
        'UTF-16 input without byte order mark needs a declaration naming UTF-16LE or UTF-16BE');
    if Lbl = elUtf16 then
      RaiseDeclError('UTF-16 input without byte order mark');
    if not (((Lbl = elUtf16LE) and not BigEndian) or ((Lbl = elUtf16BE) and BigEndian)) then
      RaiseDeclError('Input is ' + LandrixXmlEncodingName(FSourceEncoding) +
        ', declaration says "' + Name + '"');
  end;
end;

procedure TLandrixXmlInput.UseInPlaceUtf8(Body: PAnsiChar; Len: Integer);
var
  I, N, Line, Column: Integer;
  CodePoint: Cardinal;
begin
  I := 0;
  while I < Len do
  begin
    if Ord(Body[I]) < $80 then
    begin
      if Body[I] = #0 then
      begin
        LineColumnUtf8(Body, I, Line, Column);
        RaiseAt(xecInvalidChar, 'NUL character in input', Line, Column,
          FBomSize + Int64(I));
      end;
      Inc(I);
    end
    else
    begin
      N := LandrixXmlDecodeUtf8(Body + I, Len - I, CodePoint);
      if N = 0 then
      begin
        LineColumnUtf8(Body, I, Line, Column);
        RaiseAt(xecInvalidUnicode, 'Invalid UTF-8 byte sequence', Line, Column,
          FBomSize + Int64(I));
      end;
      Inc(I, N);
    end;
  end;
  FData := Body;
  FSize := Len;
end;

procedure TLandrixXmlInput.ConvertSingleByte(Src: PAnsiChar; Len: Integer;
  Encoding: TLandrixXmlEncoding);
var
  I, O, Line, Column: Integer;
  B: Byte;
  CodePoint: Cardinal;
  Total: Int64;
  Dest: PAnsiChar;
begin
  Total := 0;
  for I := 0 to Len - 1 do
  begin
    B := Ord(Src[I]);
    if B = 0 then
    begin
      LineColumnBytes(Src, I, Line, Column);
      RaiseAt(xecInvalidChar, 'NUL character in input', Line, Column,
        FBomSize + Int64(I));
    end;
    if B < $80 then
      Inc(Total)
    else if SingleByteCodePoint(Encoding, B) < $800 then
      Inc(Total, 2)
    else
      Inc(Total, 3);
  end;
  if Total > MaxInt - 1 then
    RaiseAt(xecLimit, 'Input too large', 0, 0, -1);
  FOut.Clear;
  Dest := FOut.Extend(Integer(Total));
  O := 0;
  for I := 0 to Len - 1 do
  begin
    B := Ord(Src[I]);
    if B < $80 then
    begin
      Dest[O] := AnsiChar(B);
      Inc(O);
    end
    else
    begin
      CodePoint := SingleByteCodePoint(Encoding, B);
      Inc(O, LandrixXmlEncodeUtf8(CodePoint, Dest + O));
    end;
  end;
  FData := FOut.Data;
  if FData = nil then
    FData := @ZeroByte;
  FSize := FOut.Size;
end;

procedure TLandrixXmlInput.DecodeAsciiCompatible(Authoritative: Boolean);
var
  Body: PAnsiChar;
  Len, I, BadOffset, Line, Column: Integer;
  Decl: TLandrixXmlDeclaration;
  Lbl: TEncodingLabel;
  Name: string;
  Encoding: TLandrixXmlEncoding;
begin
  Body := FRaw.Data + FBomSize;
  Len := FRaw.Size - FBomSize;
  FSourceEncoding := xenUtf8; { for offset mapping of declaration errors }
  ReadDeclaration(Body, Len, Decl);
  Lbl := LabelFromName(Body + Decl.EncodingStart, Decl.EncodingLength);
  Name := LandrixXmlEscapeForMessage(FDeclaredEncoding, 40);

  if Authoritative then
  begin
    { LoadFromUtf8: the string type decides, the declaration is recorded }
    UseInPlaceUtf8(Body, Len);
    Exit;
  end;

  case Lbl of
    elNone, elUtf8: Encoding := xenUtf8;
    elLatin1:
      if FLatin1AsWindows1252 then
        Encoding := xenWindows1252
      else
        Encoding := xenIso88591;
    elCp1252: Encoding := xenWindows1252;
    elAscii: Encoding := xenAscii;
    elLatin9: Encoding := xenIso885915;
    elUtf16, elUtf16LE, elUtf16BE:
      begin
        if FHadBom then
          RaiseDeclError('Byte order mark indicates UTF-8, declaration says "' +
            Name + '"');
        RaiseDeclError('Declaration says "' + Name +
          '" but the input is not UTF-16');
        Encoding := xenUnknown;
      end;
  else
    RaiseDeclError('Unsupported encoding "' + Name + '"');
    Encoding := xenUnknown;
  end;
  if FHadBom and (Encoding <> xenUtf8) then
    RaiseDeclError('Byte order mark indicates UTF-8, declaration says "' +
      Name + '"');

  case Encoding of
    xenUtf8:
      begin
        if (FFallbackEncoding <> xenUnknown) and not FHadBom and
          not LandrixXmlValidateUtf8Buf(Body, Len, BadOffset) then
        begin
          FSourceEncoding := FFallbackEncoding;
          ConvertSingleByte(Body, Len, FFallbackEncoding);
        end
        else
          UseInPlaceUtf8(Body, Len);
      end;
    xenAscii:
      begin
        FSourceEncoding := xenAscii;
        for I := 0 to Len - 1 do
          if Ord(Body[I]) >= $80 then
          begin
            LineColumnBytes(Body, I, Line, Column);
            RaiseAt(xecEncoding, 'Byte >= $80 in US-ASCII input', Line, Column,
              FBomSize + Int64(I));
          end;
        UseInPlaceUtf8(Body, Len);
      end;
  else
    FSourceEncoding := Encoding;
    ConvertSingleByte(Body, Len, Encoding);
  end;
end;

function TLandrixXmlInput.OriginalOffset(Utf8Offset: Integer): Int64;
var
  I, Units: Integer;
  B: Byte;
begin
  if Utf8Offset < 0 then
  begin
    Result := -1;
    Exit;
  end;
  if Utf8Offset > FSize then
    Utf8Offset := FSize;
  case FSourceEncoding of
    xenIso88591, xenWindows1252, xenIso885915:
      begin
        { one original byte per character }
        Result := 0;
        for I := 0 to Utf8Offset - 1 do
          if (Ord(FData[I]) and $C0) <> $80 then
            Inc(Result);
        Inc(Result, FBomSize);
      end;
    xenUtf16LE, xenUtf16BE:
      begin
        Units := 0;
        for I := 0 to Utf8Offset - 1 do
        begin
          B := Ord(FData[I]);
          if B >= $F0 then
            Inc(Units, 2)
          else if (B and $C0) <> $80 then
            Inc(Units);
        end;
        Result := FBomSize + 2 * Int64(Units);
      end;
  else
    Result := FBomSize + Int64(Utf8Offset);
  end;
end;

end.
