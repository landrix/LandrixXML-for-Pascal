{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Pull reader for well-formed XML 1.0 with namespaces.

  Usage:
    Reader := TLandrixXmlReader.Create;
    try
      Reader.LoadFromFile('invoice.xml');
      while Reader.Read do
        case Reader.TokenType of
          xttStartElement: ... Reader.LocalNameUtf8, Reader.NamespaceUriUtf8,
                               Reader.AttributeCount, Reader.AttributeValueUtf8(I)
          xttText:         ... Reader.ValueUtf8
          xttEndElement:   ...
        end;
    finally
      Reader.Free;
    end;

  Rules (see PLAN.md decision log):
  - Every element yields xttStartElement and xttEndElement, also <x/>
    (IsEmptyElement is informative). The root element has depth 0.
  - Text is coalesced across entity and character references. CDATA
    sections are separate tokens. Whitespace-only text is reported with
    IsWhitespace = True (a run containing a reference never counts as
    whitespace). Whitespace outside the root element is not reported.
  - Line ends are normalized to LF everywhere. Attribute values are
    normalized (TAB, CR, LF become a space; character references are kept).
  - Namespaces are always processed. xmlns attributes are reported as
    attributes in the namespace http://www.w3.org/2000/xmlns/.
  - A DOCTYPE is skipped and reported as xttDocumentType; entities declared
    in it are NOT expanded, references to them are errors.
  - Spans (TLandrixXmlSpan) point into internal memory and are valid until
    the next Read, Skip or load. Use the ...Utf8, ...W or native accessors
    for copies.
  - After an error the reader is dead: Read raises xecInvalidOperation.
    Stopping early leaves the rest of the document unchecked. }

unit LandrixXmlReader;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  Classes,
  LandrixXmlBase,
  LandrixXmlEncoding;

const
  LandrixXmlNamespaceXml = 'http://www.w3.org/XML/1998/namespace';
  LandrixXmlNamespaceXmlns = 'http://www.w3.org/2000/xmlns/';
  LandrixXmlDefaultMaxDepth = 256;

type
  { Append-only: never reorder or remove values. }
  TLandrixXmlTokenType = (
    xttNone,
    xttStartElement,
    xttEndElement,
    xttText,
    xttCData,
    xttComment,
    xttProcessingInstruction,
    xttDocumentType,
    xttEndOfDocument
  );

  { Zero-copy view of UTF-8 bytes. Not #0-terminated. }
  TLandrixXmlSpan = record
    P: PAnsiChar;
    Len: Integer;
  end;

  TLandrixXmlReader = class;

  { Push adapter: override the methods you need and pass the handler to
    TLandrixXmlReader.Run. The reader is positioned on the token. }
  TLandrixXmlHandler = class
  public
    procedure StartElement(Reader: TLandrixXmlReader); virtual;
    procedure EndElement(Reader: TLandrixXmlReader); virtual;
    procedure Text(Reader: TLandrixXmlReader); virtual;
    procedure CData(Reader: TLandrixXmlReader); virtual;
    procedure Comment(Reader: TLandrixXmlReader); virtual;
    procedure ProcessingInstruction(Reader: TLandrixXmlReader); virtual;
    procedure DocumentType(Reader: TLandrixXmlReader); virtual;
    procedure EndDocument(Reader: TLandrixXmlReader); virtual;
  end;

  { Internal bookkeeping records (public only because class fields need
    them). }
  TLandrixXmlReaderAttr = record
    NameP: PAnsiChar;
    NameLen: Integer;
    ColonPos: Integer;
    ValueP: PAnsiChar;
    ValueLen: Integer;
    ValueOfs: Integer; { offset in the scratch buffer, -1 = in the input }
    NsP: PAnsiChar;
    NsLen: Integer;
    IsNsDecl: Boolean;
  end;

  TLandrixXmlReaderElement = record
    NameP: PAnsiChar;
    NameLen: Integer;
    ColonPos: Integer;
    NsP: PAnsiChar;
    NsLen: Integer;
    BindingTop: Integer;
  end;

  TLandrixXmlReaderBinding = record
    PrefixP: PAnsiChar;
    PrefixLen: Integer;
    Uri: TLandrixXmlUtf8;
  end;

  TLandrixXmlReader = class
  private
    FInput: TLandrixXmlInput;
    FScratch: TLandrixXmlBuffer;
    FBase: PAnsiChar;
    FEnd: PAnsiChar;
    FCur: PAnsiChar;
    FState: Integer;
    FMaxDepth: Integer;
    FToken: TLandrixXmlTokenType;
    FTokenStart: PAnsiChar;
    FDepth: Integer;
    FIsEmpty: Boolean;
    FIsWhitespace: Boolean;
    FNameP: PAnsiChar;
    FNameLen: Integer;
    FColonPos: Integer;
    FNsP: PAnsiChar;
    FNsLen: Integer;
    FValueP: PAnsiChar;
    FValueLen: Integer;
    FValueOfs: Integer;
    FAttrs: array of TLandrixXmlReaderAttr;
    FAttrCount: Integer;
    FElems: array of TLandrixXmlReaderElement;
    FElemCount: Integer;
    FBindings: array of TLandrixXmlReaderBinding;
    FBindingCount: Integer;
    FHashTable: array of Integer;
    FPendingEnd: Boolean;
    FPendingPop: Boolean;
    FHasDocType: Boolean;
    FVersion: TLandrixXmlUtf8;
    FStandalone: TLandrixXmlUtf8;
    { lazy line/column checkpoint }
    FPosOfs: Integer;
    FPosLine: Integer;
    FPosColumn: Integer;
    FPosAfterCR: Boolean;
    procedure SetMaxDepth(Value: Integer);
    procedure Restart;
    procedure Fail(Code: TLandrixXmlErrorCode; const Msg: string; At: PAnsiChar);
    procedure CheckLiveState;
    procedure LineColumnAt(Ofs: Integer; out Line, Column: Integer);
    procedure ReadXmlDeclaration;
    function ReadNext: Boolean;
    procedure PopElement;
    procedure SetEndToken;
    function ScanName(var P: PAnsiChar): Integer;
    function CheckQName(Start: PAnsiChar; Len: Integer): Integer;
    procedure CheckSpecialChar(P: PAnsiChar);
    procedure DecodeInto(Start, Stop: PAnsiChar; Mode: Integer);
    function ParseReference(P: PAnsiChar; Stop: PAnsiChar): PAnsiChar;
    procedure ReadStartTag;
    procedure ReadEndTag;
    procedure ReadText;
    procedure ReadComment;
    procedure ReadCData;
    procedure ReadProcessingInstruction;
    procedure ReadDocType;
    procedure ProcessNamespaces;
    procedure CheckDuplicates(Expanded: Boolean);
    function FindBinding(PrefixP: PAnsiChar; PrefixLen: Integer): Integer;
    function GetValueSpan: TLandrixXmlSpan;
    function GetNameSpan: TLandrixXmlSpan;
    function GetPrefixSpan: TLandrixXmlSpan;
    function GetLocalNameSpan: TLandrixXmlSpan;
    function GetNamespaceUriSpan: TLandrixXmlSpan;
    procedure CheckAttrIndex(Index: Integer);
  public
    constructor Create;
    destructor Destroy; override;

    procedure LoadFromFile(const FileName: string);
    procedure LoadFromStream(Stream: TStream);
    procedure LoadFromBuffer(const Data; Size: Integer);
    procedure LoadFromUtf8(const S: TLandrixXmlUtf8);
    procedure LoadFromString(const S: string);

    { Advances to the next token. Returns False at the end of the document
      (TokenType = xttEndOfDocument). }
    function Read: Boolean;
    { On xttStartElement: reads (and checks) the whole subtree and stops on
      the matching xttEndElement. Otherwise does nothing. }
    procedure Skip;
    { Reads all remaining tokens (from the current position) and passes them
      to Handler, then calls Handler.EndDocument. }
    procedure Run(Handler: TLandrixXmlHandler);

    property TokenType: TLandrixXmlTokenType read FToken;
    { Element depth (root = 0) for element tokens; for other tokens the
      depth of their parent element plus one (0 outside the root). }
    property Depth: Integer read FDepth;
    { True on both the start and the end token of an empty element <x/>. }
    property IsEmptyElement: Boolean read FIsEmpty;
    property IsWhitespace: Boolean read FIsWhitespace;

    { Element name (elements), target (processing instruction) or root
      name (document type). }
    property NameSpan: TLandrixXmlSpan read GetNameSpan;
    property PrefixSpan: TLandrixXmlSpan read GetPrefixSpan;
    property LocalNameSpan: TLandrixXmlSpan read GetLocalNameSpan;
    property NamespaceUriSpan: TLandrixXmlSpan read GetNamespaceUriSpan;
    { Text, CDATA, comment, processing instruction data, raw DOCTYPE
      content. }
    property ValueSpan: TLandrixXmlSpan read GetValueSpan;

    function NameUtf8: TLandrixXmlUtf8;
    function PrefixUtf8: TLandrixXmlUtf8;
    function LocalNameUtf8: TLandrixXmlUtf8;
    function NamespaceUriUtf8: TLandrixXmlUtf8;
    function ValueUtf8: TLandrixXmlUtf8;
    function LocalNameW: TLandrixXmlWide;
    function NamespaceUriW: TLandrixXmlWide;
    function ValueW: TLandrixXmlWide;
    function Name: string;
    function LocalName: string;
    function NamespaceUri: string;
    function Value: string;

    { Attributes of the current start element, zero-based, source order. }
    property AttributeCount: Integer read FAttrCount;
    function AttributeNameSpan(Index: Integer): TLandrixXmlSpan;
    function AttributePrefixSpan(Index: Integer): TLandrixXmlSpan;
    function AttributeLocalNameSpan(Index: Integer): TLandrixXmlSpan;
    function AttributeNamespaceUriSpan(Index: Integer): TLandrixXmlSpan;
    function AttributeValueSpan(Index: Integer): TLandrixXmlSpan;
    function AttributeNameUtf8(Index: Integer): TLandrixXmlUtf8;
    function AttributeLocalNameUtf8(Index: Integer): TLandrixXmlUtf8;
    function AttributeNamespaceUriUtf8(Index: Integer): TLandrixXmlUtf8;
    function AttributeValueUtf8(Index: Integer): TLandrixXmlUtf8;
    function AttributeValueW(Index: Integer): TLandrixXmlWide;
    function AttributeValue(Index: Integer): string;
    function IsNamespaceDeclaration(Index: Integer): Boolean;
    { Index of the attribute with this expanded name, -1 if absent. Use ''
      as NamespaceUri for unprefixed attributes. }
    function AttributeIndex(const NamespaceUri, LocalName: TLandrixXmlUtf8): Integer;
    { Namespace URI bound to Prefix ('' = default namespace) in the current
      scope. False if the prefix is not bound. }
    function LookupNamespace(const Prefix: TLandrixXmlUtf8;
      out Uri: TLandrixXmlUtf8): Boolean;

    { From the XML declaration; '' if absent. }
    property Version: TLandrixXmlUtf8 read FVersion;
    property Standalone: TLandrixXmlUtf8 read FStandalone;
    property HasDocumentType: Boolean read FHasDocType;

    { Position of the current token's first character. Line/Column are
      computed on demand (cheap for ascending use). }
    function Line: Integer;
    function Column: Integer;
    function Offset: Int64;

    property Input: TLandrixXmlInput read FInput;
    property MaxDepth: Integer read FMaxDepth write SetMaxDepth;
  end;

function LandrixXmlSpanToUtf8(const Span: TLandrixXmlSpan): TLandrixXmlUtf8;
function LandrixXmlSpanEquals(const Span: TLandrixXmlSpan;
  const S: TLandrixXmlUtf8): Boolean;

implementation

const
  { reader states }
  rsInitial = 0;
  rsProlog = 1;
  rsContent = 2;
  rsEpilog = 3;
  rsEnd = 4;
  rsError = 5;

  { DecodeInto modes }
  dmText = 0;      { references, CR LF / CR -> LF }
  dmAttribute = 1; { references, TAB/LF/CR -> space, CR LF -> one space }
  dmRaw = 2;       { CR LF / CR -> LF only (comments, PIs, CDATA) }

  { duplicate check: below this count a quadratic check is cheaper }
  HashThreshold = 12;

type
  TAnsiCharSet = set of AnsiChar;

const
  NameStartAscii: TAnsiCharSet = ['A'..'Z', 'a'..'z', '_', ':'];
  NameAscii: TAnsiCharSet = ['A'..'Z', 'a'..'z', '_', ':', '0'..'9', '-', '.'];
  SpaceChars: TAnsiCharSet = [' ', #9, #10, #13];

{ --- spans -------------------------------------------------------------- }

function MakeSpan(P: PAnsiChar; Len: Integer): TLandrixXmlSpan;
begin
  Result.P := P;
  Result.Len := Len;
end;

function LandrixXmlSpanToUtf8(const Span: TLandrixXmlSpan): TLandrixXmlUtf8;
begin
  Result := '';
  if Span.Len > 0 then
  begin
    SetLength(Result, Span.Len);
    Move(Span.P^, PAnsiChar(Result)^, Span.Len);
  end;
end;

function SameBytes(P1: PAnsiChar; Len1: Integer; P2: PAnsiChar; Len2: Integer): Boolean;
var
  I: Integer;
begin
  Result := Len1 = Len2;
  I := 0;
  while Result and (I < Len1) do
  begin
    Result := P1[I] = P2[I];
    Inc(I);
  end;
end;

function LandrixXmlSpanEquals(const Span: TLandrixXmlSpan;
  const S: TLandrixXmlUtf8): Boolean;
begin
  Result := SameBytes(Span.P, Span.Len, PAnsiChar(S), Length(S));
end;

function SpanEqualsAscii(P: PAnsiChar; Len: Integer; const S: AnsiString): Boolean;
begin
  Result := SameBytes(P, Len, PAnsiChar(S), Length(S));
end;

function HashBytes(P: PAnsiChar; Len: Integer; Seed: Cardinal): Cardinal;
var
  I: Integer;
begin
  { FNV-1a }
  Result := Seed;
  for I := 0 to Len - 1 do
    { computed in Int64 and masked: the wrap-around is intended and must not
      trip overflow or range checking in projects compiled with Q+/R+ }
    Result := Cardinal((Int64(Result xor Ord(P[I])) * 16777619) and $FFFFFFFF);
end;

{ --- name characters (XML 1.0 fifth edition) ------------------------------ }

function IsNameStartCodePoint(C: Cardinal): Boolean;
begin
  if C < $80 then
    Result := AnsiChar(C) in NameStartAscii
  else
    Result := ((C >= $C0) and (C <= $D6)) or ((C >= $D8) and (C <= $F6)) or
      ((C >= $F8) and (C <= $2FF)) or ((C >= $370) and (C <= $37D)) or
      ((C >= $37F) and (C <= $1FFF)) or ((C >= $200C) and (C <= $200D)) or
      ((C >= $2070) and (C <= $218F)) or ((C >= $2C00) and (C <= $2FEF)) or
      ((C >= $3001) and (C <= $D7FF)) or ((C >= $F900) and (C <= $FDCF)) or
      ((C >= $FDF0) and (C <= $FFFD)) or ((C >= $10000) and (C <= $EFFFF));
end;

function IsNameCodePoint(C: Cardinal): Boolean;
begin
  if C < $80 then
    Result := AnsiChar(C) in NameAscii
  else
    Result := IsNameStartCodePoint(C) or (C = $B7) or
      ((C >= $300) and (C <= $36F)) or ((C >= $203F) and (C <= $2040));
end;

{ --- TLandrixXmlHandler --------------------------------------------------- }

{ the default implementations ignore their parameter }
{$IFDEF FPC}
  {$PUSH}
  {$WARN 5024 OFF}
{$ENDIF}

procedure TLandrixXmlHandler.StartElement(Reader: TLandrixXmlReader);
begin
end;

procedure TLandrixXmlHandler.EndElement(Reader: TLandrixXmlReader);
begin
end;

procedure TLandrixXmlHandler.Text(Reader: TLandrixXmlReader);
begin
end;

procedure TLandrixXmlHandler.CData(Reader: TLandrixXmlReader);
begin
end;

procedure TLandrixXmlHandler.Comment(Reader: TLandrixXmlReader);
begin
end;

procedure TLandrixXmlHandler.ProcessingInstruction(Reader: TLandrixXmlReader);
begin
end;

procedure TLandrixXmlHandler.DocumentType(Reader: TLandrixXmlReader);
begin
end;

procedure TLandrixXmlHandler.EndDocument(Reader: TLandrixXmlReader);
begin
end;

{$IFDEF FPC}
  {$POP}
{$ENDIF}

{ --- TLandrixXmlReader: setup ---------------------------------------------- }

constructor TLandrixXmlReader.Create;
begin
  inherited Create;
  FInput := TLandrixXmlInput.Create;
  FScratch := TLandrixXmlBuffer.Create;
  FMaxDepth := LandrixXmlDefaultMaxDepth;
  Restart;
end;

destructor TLandrixXmlReader.Destroy;
begin
  FScratch.Free;
  FInput.Free;
  inherited Destroy;
end;

procedure TLandrixXmlReader.SetMaxDepth(Value: Integer);
begin
  if Value < 1 then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'MaxDepth must be at least 1');
  FMaxDepth := Value;
end;

procedure TLandrixXmlReader.Restart;
var
  I: Integer;
begin
  for I := 1 to FBindingCount - 1 do
    FBindings[I].Uri := '';
  FBase := FInput.Data;
  FEnd := FBase + FInput.Size;
  FCur := FBase;
  FState := rsInitial;
  FToken := xttNone;
  FTokenStart := FBase;
  FDepth := 0;
  FIsEmpty := False;
  FIsWhitespace := False;
  FNameP := nil;
  FNameLen := 0;
  FColonPos := -1;
  FNsP := nil;
  FNsLen := 0;
  FValueP := nil;
  FValueLen := 0;
  FValueOfs := -1;
  FAttrCount := 0;
  FElemCount := 0;
  { binding 0: the fixed xml prefix }
  FBindingCount := 1;
  if Length(FBindings) = 0 then
    SetLength(FBindings, 16);
  FBindings[0].PrefixP := 'xml';
  FBindings[0].PrefixLen := 3;
  FBindings[0].Uri := LandrixXmlNamespaceXml;
  FPendingEnd := False;
  FPendingPop := False;
  FHasDocType := False;
  FVersion := '';
  FStandalone := '';
  FPosOfs := 0;
  FPosLine := 1;
  FPosColumn := 1;
  FPosAfterCR := False;
  FScratch.Clear;
end;

procedure TLandrixXmlReader.LoadFromFile(const FileName: string);
begin
  try
    FInput.LoadFromFile(FileName);
  finally
    Restart;
  end;
end;

procedure TLandrixXmlReader.LoadFromStream(Stream: TStream);
begin
  try
    FInput.LoadFromStream(Stream);
  finally
    Restart;
  end;
end;

procedure TLandrixXmlReader.LoadFromBuffer(const Data; Size: Integer);
var
  Src: PAnsiChar;
begin
  Src := PAnsiChar(@Data);
  try
    FInput.LoadFromBuffer(Src^, Size);
  finally
    Restart;
  end;
end;

procedure TLandrixXmlReader.LoadFromUtf8(const S: TLandrixXmlUtf8);
begin
  try
    FInput.LoadFromUtf8(S);
  finally
    Restart;
  end;
end;

procedure TLandrixXmlReader.LoadFromString(const S: string);
begin
  LoadFromUtf8(LandrixXmlStringToUtf8(S));
end;

{ --- errors and positions --------------------------------------------------- }

procedure TLandrixXmlReader.LineColumnAt(Ofs: Integer; out Line, Column: Integer);
var
  I: Integer;
  C: AnsiChar;
begin
  if Ofs < FPosOfs then
  begin
    FPosOfs := 0;
    FPosLine := 1;
    FPosColumn := 1;
    FPosAfterCR := False;
  end;
  for I := FPosOfs to Ofs - 1 do
  begin
    C := FBase[I];
    if C = #13 then
    begin
      Inc(FPosLine);
      FPosColumn := 1;
      FPosAfterCR := True;
    end
    else
    begin
      if C = #10 then
      begin
        if not FPosAfterCR then
        begin
          Inc(FPosLine);
          FPosColumn := 1;
        end;
      end
      else if (Ord(C) and $C0) <> $80 then
        Inc(FPosColumn);
      FPosAfterCR := False;
    end;
  end;
  FPosOfs := Ofs;
  Line := FPosLine;
  Column := FPosColumn;
end;

procedure TLandrixXmlReader.Fail(Code: TLandrixXmlErrorCode; const Msg: string;
  At: PAnsiChar);
var
  Ofs, Line, Column: Integer;
begin
  FState := rsError;
  if At < FBase then
    At := FBase;
  if At > FEnd then
    At := FEnd;
  Ofs := Integer(At - FBase);
  LineColumnAt(Ofs, Line, Column);
  raise ELandrixXmlError.CreateAt(Code, Msg, Line, Column,
    FInput.OriginalOffset(Ofs));
end;

procedure TLandrixXmlReader.CheckLiveState;
begin
  if FState = rsError then
    raise ELandrixXmlError.CreateCode(xecInvalidOperation,
      'The reader stopped after an error');
end;

function TLandrixXmlReader.Line: Integer;
var
  Column: Integer;
begin
  LineColumnAt(Integer(FTokenStart - FBase), Result, Column);
end;

function TLandrixXmlReader.Column: Integer;
var
  Line: Integer;
begin
  LineColumnAt(Integer(FTokenStart - FBase), Line, Result);
end;

function TLandrixXmlReader.Offset: Int64;
begin
  Result := FInput.OriginalOffset(Integer(FTokenStart - FBase));
end;

{ --- low-level scanning ---------------------------------------------------- }

{ Characters >= $80 are valid UTF-8 (checked by the input layer), so only
  U+FFFE and U+FFFF (EF BF BE / EF BF BF) can be invalid XML characters. }
procedure TLandrixXmlReader.CheckSpecialChar(P: PAnsiChar);
begin
  if Ord(P^) < $20 then
  begin
    if not ((P^ = #9) or (P^ = #10) or (P^ = #13)) then
      Fail(xecInvalidChar, 'Character U+' + IntToHex(Ord(P^), 4) +
        ' is not allowed in XML', P);
  end
  else if (P^ = #$EF) and (P[1] = #$BF) and (P[2] = #$BE) then
    Fail(xecInvalidChar, 'Character U+FFFE is not allowed in XML', P)
  else if (P^ = #$EF) and (P[1] = #$BF) and (P[2] = #$BF) then
    Fail(xecInvalidChar, 'Character U+FFFF is not allowed in XML', P);
end;

function TLandrixXmlReader.ScanName(var P: PAnsiChar): Integer;
var
  Start: PAnsiChar;
  N: Integer;
  CodePoint: Cardinal;
begin
  Start := P;
  if Ord(P^) < $80 then
  begin
    if not (P^ in NameStartAscii) then
      Fail(xecSyntax, 'Name expected', P);
    Inc(P);
  end
  else
  begin
    N := LandrixXmlDecodeUtf8(P, Integer(FEnd - P), CodePoint);
    if (N = 0) or not IsNameStartCodePoint(CodePoint) then
      Fail(xecSyntax, 'Name expected', P);
    Inc(P, N);
  end;
  while True do
  begin
    if Ord(P^) < $80 then
    begin
      if P^ in NameAscii then
        Inc(P)
      else
        Break;
    end
    else
    begin
      N := LandrixXmlDecodeUtf8(P, Integer(FEnd - P), CodePoint);
      if (N > 0) and IsNameCodePoint(CodePoint) then
        Inc(P, N)
      else
        Break;
    end;
  end;
  Result := Integer(P - Start);
end;

{ Namespaces: a QName has at most one colon, not at either end, and the
  local part starts with a name start character. Returns the colon
  position or -1. }
function TLandrixXmlReader.CheckQName(Start: PAnsiChar; Len: Integer): Integer;
var
  I, N: Integer;
  CodePoint: Cardinal;
begin
  Result := -1;
  for I := 0 to Len - 1 do
    if Start[I] = ':' then
    begin
      if Result >= 0 then
        Fail(xecNamespace, 'Qualified name with more than one colon', Start + I);
      Result := I;
    end;
  if Result < 0 then
    Exit;
  if (Result = 0) or (Result = Len - 1) then
    Fail(xecNamespace, 'Qualified name with empty prefix or local part', Start + Result);
  N := LandrixXmlDecodeUtf8(Start + Result + 1, Len - Result - 1, CodePoint);
  if (N = 0) or (CodePoint = Ord(':')) or not IsNameStartCodePoint(CodePoint) then
    Fail(xecNamespace, 'Invalid local name in qualified name', Start + Result + 1);
end;

{ Value of a decimal or (Hex) hexadecimal digit, -1 if C is none. }
function DigitValue(C: AnsiChar; Hex: Boolean): Integer;
begin
  if (C >= '0') and (C <= '9') then
    Result := Ord(C) - Ord('0')
  else if Hex and (C >= 'a') and (C <= 'f') then
    Result := Ord(C) - Ord('a') + 10
  else if Hex and (C >= 'A') and (C <= 'F') then
    Result := Ord(C) - Ord('A') + 10
  else
    Result := -1;
end;

{ Parses the reference at P ('&'), appends its value to the scratch buffer
  and returns the position after ';'. }
function TLandrixXmlReader.ParseReference(P: PAnsiChar; Stop: PAnsiChar): PAnsiChar;
var
  Q, NameStart: PAnsiChar;
  CodePoint: Cardinal;
  Digit: Integer;
  Overflow, Hex: Boolean;
  NameLen: Integer;
begin
  Q := P + 1;
  if Q^ = '#' then
  begin
    Inc(Q);
    Hex := Q^ = 'x';
    if Hex then
      Inc(Q);
    CodePoint := 0;
    Overflow := False;
    NameStart := Q;
    while Q < Stop do
    begin
      Digit := DigitValue(Q^, Hex);
      if Digit < 0 then
        Break;
      if not Overflow then
      begin
        if Hex then
          CodePoint := CodePoint * 16 + Cardinal(Digit)
        else
          CodePoint := CodePoint * 10 + Cardinal(Digit);
        if CodePoint > LandrixXmlMaxCodePoint then
          Overflow := True;
      end;
      Inc(Q);
    end;
    if (Q = NameStart) or (Q >= Stop) or (Q^ <> ';') then
      Fail(xecSyntax, 'Malformed character reference', P);
    if Overflow or not LandrixXmlIsXmlChar(CodePoint) then
      Fail(xecInvalidChar, 'Character reference to a character that is not allowed in XML', P);
    FScratch.AppendCodePoint(CodePoint);
    Result := Q + 1;
    Exit;
  end;
  NameStart := Q;
  NameLen := ScanName(Q);
  if (Q >= Stop) or (Q^ <> ';') then
    Fail(xecSyntax, 'Malformed entity reference', P);
  if SpanEqualsAscii(NameStart, NameLen, 'lt') then
    FScratch.AppendByte(Ord('<'))
  else if SpanEqualsAscii(NameStart, NameLen, 'gt') then
    FScratch.AppendByte(Ord('>'))
  else if SpanEqualsAscii(NameStart, NameLen, 'amp') then
    FScratch.AppendByte(Ord('&'))
  else if SpanEqualsAscii(NameStart, NameLen, 'apos') then
    FScratch.AppendByte(Ord(''''))
  else if SpanEqualsAscii(NameStart, NameLen, 'quot') then
    FScratch.AppendByte(Ord('"'))
  else if FHasDocType then
    Fail(xecSyntax, 'Entity &' + LandrixXmlEscapeForMessage(
      LandrixXmlSpanToUtf8(MakeSpan(NameStart, NameLen)), 40) +
      '; is not expanded: DTD entities are not supported', P)
  else
    Fail(xecSyntax, 'Undeclared entity &' + LandrixXmlEscapeForMessage(
      LandrixXmlSpanToUtf8(MakeSpan(NameStart, NameLen)), 40) + ';', P);
  Result := Q + 1;
end;

{ Appends [Start, Stop) to the scratch buffer with normalization. The
  characters were already checked by the caller. }
procedure TLandrixXmlReader.DecodeInto(Start, Stop: PAnsiChar; Mode: Integer);
var
  P, Run: PAnsiChar;
begin
  P := Start;
  Run := Start;
  while P < Stop do
  begin
    case P^ of
      #13:
        begin
          FScratch.Append(Run^, Integer(P - Run));
          if Mode = dmAttribute then
            FScratch.AppendByte(Ord(' '))
          else
            FScratch.AppendByte(10);
          Inc(P);
          if (P < Stop) and (P^ = #10) then
            Inc(P);
          Run := P;
        end;
      #9, #10:
        if Mode = dmAttribute then
        begin
          FScratch.Append(Run^, Integer(P - Run));
          FScratch.AppendByte(Ord(' '));
          Inc(P);
          Run := P;
        end
        else
          Inc(P);
      '&':
        if Mode <> dmRaw then
        begin
          FScratch.Append(Run^, Integer(P - Run));
          P := ParseReference(P, Stop);
          Run := P;
        end
        else
          Inc(P);
    else
      Inc(P);
    end;
  end;
  FScratch.Append(Run^, Integer(Stop - Run));
end;

{ --- declaration ------------------------------------------------------------ }

procedure TLandrixXmlReader.ReadXmlDeclaration;
var
  Decl: TLandrixXmlDeclaration;
  ErrorOffset: Integer;
begin
  if not LandrixXmlScanDeclaration(FBase, Integer(FEnd - FBase), Decl, ErrorOffset) then
    Fail(xecSyntax, 'Malformed XML declaration', FBase + ErrorOffset);
  if Decl.Present then
  begin
    FVersion := LandrixXmlSpanToUtf8(MakeSpan(FBase + Decl.VersionStart, Decl.VersionLength));
    FStandalone := LandrixXmlSpanToUtf8(MakeSpan(FBase + Decl.StandaloneStart, Decl.StandaloneLength));
    FCur := FBase + Decl.EndOffset;
  end;
end;

{ --- token readers ---------------------------------------------------------- }

procedure TLandrixXmlReader.ReadText;
var
  P: PAnsiChar;
  NeedsDecode, IsSpace: Boolean;
begin
  P := FCur;
  NeedsDecode := False;
  IsSpace := True;
  while True do
  begin
    case P^ of
      '<':
        Break;
      #0:
        if P >= FEnd then
          Break
        else
          CheckSpecialChar(P);
      ' ', #9, #10:
        ;
      #13:
        NeedsDecode := True;
      '&':
        begin
          NeedsDecode := True;
          IsSpace := False;
        end;
      ']':
        begin
          if (P[1] = ']') and (P[2] = '>') then
            Fail(xecSyntax, '"]]>" is not allowed in text', P);
          IsSpace := False;
        end;
    else
      IsSpace := False;
      if (Ord(P^) < $20) or (P^ = #$EF) then
        CheckSpecialChar(P);
    end;
    Inc(P);
  end;
  FToken := xttText;
  FIsWhitespace := IsSpace;
  if NeedsDecode then
  begin
    FValueOfs := FScratch.Size;
    DecodeInto(FCur, P, dmText);
    FValueLen := FScratch.Size - FValueOfs;
  end
  else
  begin
    FValueP := FCur;
    FValueLen := Integer(P - FCur);
  end;
  FCur := P;
end;

procedure TLandrixXmlReader.ReadComment;
var
  P, Start: PAnsiChar;
  NeedsDecode: Boolean;
begin
  P := FCur + 4;
  Start := P;
  NeedsDecode := False;
  while True do
  begin
    if P >= FEnd then
      Fail(xecSyntax, 'Unterminated comment', FCur);
    if (P^ = '-') and (P[1] = '-') then
    begin
      if P[2] = '>' then
        Break;
      Fail(xecSyntax, '"--" is not allowed in comments', P);
    end;
    if P^ = #13 then
      NeedsDecode := True
    else if (Ord(P^) < $20) or (P^ = #$EF) then
      CheckSpecialChar(P);
    Inc(P);
  end;
  FToken := xttComment;
  if NeedsDecode then
  begin
    FValueOfs := FScratch.Size;
    DecodeInto(Start, P, dmRaw);
    FValueLen := FScratch.Size - FValueOfs;
  end
  else
  begin
    FValueP := Start;
    FValueLen := Integer(P - Start);
  end;
  FCur := P + 3;
end;

procedure TLandrixXmlReader.ReadCData;
var
  P, Start: PAnsiChar;
  NeedsDecode: Boolean;
begin
  P := FCur + 9;
  Start := P;
  NeedsDecode := False;
  while True do
  begin
    if P >= FEnd then
      Fail(xecSyntax, 'Unterminated CDATA section', FCur);
    if (P^ = ']') and (P[1] = ']') and (P[2] = '>') then
      Break;
    if P^ = #13 then
      NeedsDecode := True
    else if (Ord(P^) < $20) or (P^ = #$EF) then
      CheckSpecialChar(P);
    Inc(P);
  end;
  FToken := xttCData;
  if NeedsDecode then
  begin
    FValueOfs := FScratch.Size;
    DecodeInto(Start, P, dmRaw);
    FValueLen := FScratch.Size - FValueOfs;
  end
  else
  begin
    FValueP := Start;
    FValueLen := Integer(P - Start);
  end;
  FCur := P + 3;
end;

procedure TLandrixXmlReader.ReadProcessingInstruction;
var
  P, Start: PAnsiChar;
  NeedsDecode: Boolean;
  I: Integer;
begin
  P := FCur + 2;
  FNameP := P;
  FNameLen := ScanName(P);
  for I := 0 to FNameLen - 1 do
    if FNameP[I] = ':' then
      Fail(xecNamespace, 'Processing instruction target must not contain a colon',
        FNameP + I);
  FColonPos := -1;
  if (FNameLen = 3) and (FNameP[0] in ['x', 'X']) and (FNameP[1] in ['m', 'M']) and
    (FNameP[2] in ['l', 'L']) then
  begin
    if (FCur = FBase) and (FState = rsProlog) then
      Fail(xecSyntax, 'Malformed XML declaration', FCur)
    else
      Fail(xecSyntax, 'The XML declaration is only allowed at the very start of the document; ' +
        'processing instruction targets "xml" are reserved', FCur);
  end;
  NeedsDecode := False;
  if (P^ = '?') and (P[1] = '>') then
    Start := P
  else
  begin
    if not (P^ in SpaceChars) then
      Fail(xecSyntax, 'White space expected after processing instruction target', P);
    while P^ in SpaceChars do
      Inc(P);
    Start := P;
    while True do
    begin
      if P >= FEnd then
        Fail(xecSyntax, 'Unterminated processing instruction', FCur);
      if (P^ = '?') and (P[1] = '>') then
        Break;
      if P^ = #13 then
        NeedsDecode := True
      else if (Ord(P^) < $20) or (P^ = #$EF) then
        CheckSpecialChar(P);
      Inc(P);
    end;
  end;
  FToken := xttProcessingInstruction;
  if NeedsDecode then
  begin
    FValueOfs := FScratch.Size;
    DecodeInto(Start, P, dmRaw);
    FValueLen := FScratch.Size - FValueOfs;
  end
  else
  begin
    FValueP := Start;
    FValueLen := Integer(P - Start);
  end;
  FCur := P + 2;
end;

procedure TLandrixXmlReader.ReadDocType;
var
  P, Start: PAnsiChar;
  Quote: AnsiChar;
  InSubset, NeedsDecode: Boolean;
begin
  P := FCur + 9;
  if not (P^ in SpaceChars) then
    Fail(xecSyntax, 'White space expected after <!DOCTYPE', P);
  while P^ in SpaceChars do
    Inc(P);
  FNameP := P;
  FNameLen := ScanName(P);
  FColonPos := -1;
  Start := P;
  InSubset := False;
  NeedsDecode := False;
  while True do
  begin
    if P >= FEnd then
      Fail(xecSyntax, 'Unterminated document type declaration', FCur);
    case P^ of
      '"', '''':
        begin
          Quote := P^;
          Inc(P);
          while P^ <> Quote do
          begin
            if P >= FEnd then
              Fail(xecSyntax, 'Unterminated literal in document type declaration', FCur);
            if P^ = #13 then
              NeedsDecode := True
            else if (Ord(P^) < $20) or (P^ = #$EF) then
              CheckSpecialChar(P);
            Inc(P);
          end;
        end;
      '[':
        if InSubset then
          Fail(xecSyntax, 'Unexpected "[" in document type declaration', P)
        else
          InSubset := True;
      ']':
        if InSubset then
          InSubset := False
        else
          Fail(xecSyntax, 'Unexpected "]" in document type declaration', P);
      '<':
        if InSubset and (P[1] = '!') and (P[2] = '-') and (P[3] = '-') then
        begin
          Inc(P, 4);
          while not ((P^ = '-') and (P[1] = '-') and (P[2] = '>')) do
          begin
            if P >= FEnd then
              Fail(xecSyntax, 'Unterminated comment', P);
            if P^ = #13 then
              NeedsDecode := True
            else if (Ord(P^) < $20) or (P^ = #$EF) then
              CheckSpecialChar(P);
            Inc(P);
          end;
          Inc(P, 2);
        end
        else if InSubset and (P[1] = '?') then
        begin
          Inc(P, 2);
          while not ((P^ = '?') and (P[1] = '>')) do
          begin
            if P >= FEnd then
              Fail(xecSyntax, 'Unterminated processing instruction', P);
            if P^ = #13 then
              NeedsDecode := True
            else if (Ord(P^) < $20) or (P^ = #$EF) then
              CheckSpecialChar(P);
            Inc(P);
          end;
          Inc(P);
        end
        else if not InSubset then
          Fail(xecSyntax, 'Unexpected "<" in document type declaration', P);
      '>':
        if not InSubset then
          Break;
      #13:
        NeedsDecode := True;
    else
      if (Ord(P^) < $20) or (P^ = #$EF) then
        CheckSpecialChar(P);
    end;
    Inc(P);
  end;
  FHasDocType := True;
  FToken := xttDocumentType;
  if NeedsDecode then
  begin
    FValueOfs := FScratch.Size;
    DecodeInto(Start, P, dmRaw);
    FValueLen := FScratch.Size - FValueOfs;
  end
  else
  begin
    FValueP := Start;
    FValueLen := Integer(P - Start);
  end;
  FCur := P + 1;
end;

{ Linear search from the innermost binding. Cost grows with the number of
  bindings in scope, which is tiny in real documents; only an element with
  thousands of declarations and prefixed attributes becomes slow. }
function TLandrixXmlReader.FindBinding(PrefixP: PAnsiChar; PrefixLen: Integer): Integer;
begin
  Result := FBindingCount - 1;
  while Result >= 0 do
  begin
    if SameBytes(FBindings[Result].PrefixP, FBindings[Result].PrefixLen, PrefixP, PrefixLen) then
      Exit;
    Dec(Result);
  end;
end;

procedure TLandrixXmlReader.CheckDuplicates(Expanded: Boolean);
var
  I, J, Size, Slot: Integer;
  H: Cardinal;

  function Same(A, B: Integer): Boolean;
  begin
    if Expanded then
      Result := SameBytes(FAttrs[A].NsP, FAttrs[A].NsLen, FAttrs[B].NsP, FAttrs[B].NsLen) and
        SameBytes(FAttrs[A].NameP + FAttrs[A].ColonPos + 1, FAttrs[A].NameLen - FAttrs[A].ColonPos - 1,
          FAttrs[B].NameP + FAttrs[B].ColonPos + 1, FAttrs[B].NameLen - FAttrs[B].ColonPos - 1)
    else
      Result := SameBytes(FAttrs[A].NameP, FAttrs[A].NameLen, FAttrs[B].NameP, FAttrs[B].NameLen);
  end;

  function Relevant(A: Integer): Boolean;
  begin
    { expanded check: only prefixed, non-xmlns attributes can collide in a
      way the lexical check did not catch }
    Result := not Expanded or ((FAttrs[A].ColonPos >= 0) and not FAttrs[A].IsNsDecl);
  end;

  procedure Duplicate(A: Integer);
  begin
    if Expanded then
      Fail(xecNamespace, 'Duplicate attribute (same namespace and local name)', FAttrs[A].NameP)
    else
      Fail(xecSyntax, 'Duplicate attribute', FAttrs[A].NameP);
  end;

begin
  if FAttrCount < 2 then
    Exit;
  if FAttrCount < HashThreshold then
  begin
    for I := 1 to FAttrCount - 1 do
      if Relevant(I) then
        for J := 0 to I - 1 do
          if Relevant(J) and Same(I, J) then
            Duplicate(I);
    Exit;
  end;
  Size := 32;
  while Size < 2 * FAttrCount do
    Size := Size * 2;
  if Length(FHashTable) < Size then
    SetLength(FHashTable, Size);
  for I := 0 to Size - 1 do
    FHashTable[I] := -1;
  for I := 0 to FAttrCount - 1 do
  begin
    if not Relevant(I) then
      Continue;
    if Expanded then
      H := HashBytes(FAttrs[I].NameP + FAttrs[I].ColonPos + 1,
        FAttrs[I].NameLen - FAttrs[I].ColonPos - 1,
        HashBytes(FAttrs[I].NsP, FAttrs[I].NsLen, 2166136261))
    else
      H := HashBytes(FAttrs[I].NameP, FAttrs[I].NameLen, 2166136261);
    Slot := Integer(H and Cardinal(Size - 1));
    while FHashTable[Slot] >= 0 do
    begin
      if Same(I, FHashTable[Slot]) then
        Duplicate(I);
      Slot := (Slot + 1) and (Size - 1);
    end;
    FHashTable[Slot] := I;
  end;
end;

{ True if the attribute is a namespace declaration; returns the declared
  prefix (length 0 for the default namespace). }
function DeclaredPrefix(const Attr: TLandrixXmlReaderAttr; out PrefixP: PAnsiChar;
  out PrefixLen: Integer): Boolean;
begin
  PrefixP := Attr.NameP;
  PrefixLen := 0;
  Result := SpanEqualsAscii(Attr.NameP, Attr.NameLen, 'xmlns');
  if not Result and (Attr.ColonPos = 5) and SpanEqualsAscii(Attr.NameP, 5, 'xmlns') then
  begin
    PrefixP := Attr.NameP + 6;
    PrefixLen := Attr.NameLen - 6;
    Result := True;
  end;
end;

procedure TLandrixXmlReader.ProcessNamespaces;
var
  I, B: Integer;
  Uri: TLandrixXmlUtf8;
  PrefixP: PAnsiChar;
  PrefixLen: Integer;
  E: ^TLandrixXmlReaderElement;
begin
  E := @FElems[FElemCount - 1];
  { 1. declarations }
  for I := 0 to FAttrCount - 1 do
  begin
    if not DeclaredPrefix(FAttrs[I], PrefixP, PrefixLen) then
      Continue;
    FAttrs[I].IsNsDecl := True;
    Uri := LandrixXmlSpanToUtf8(MakeSpan(FAttrs[I].ValueP, FAttrs[I].ValueLen));
    if SpanEqualsAscii(PrefixP, PrefixLen, 'xmlns') then
      Fail(xecNamespace, 'The prefix "xmlns" must not be declared', FAttrs[I].NameP);
    if SpanEqualsAscii(PrefixP, PrefixLen, 'xml') then
    begin
      if Uri <> LandrixXmlNamespaceXml then
        Fail(xecNamespace, 'The prefix "xml" must not be bound to another namespace', FAttrs[I].NameP);
    end
    else
    begin
      if (Uri = LandrixXmlNamespaceXml) or (Uri = LandrixXmlNamespaceXmlns) then
        Fail(xecNamespace, 'Reserved namespace name must not be declared', FAttrs[I].NameP);
      if (PrefixLen > 0) and (Uri = '') then
        Fail(xecNamespace, 'A prefix must not be bound to an empty namespace name', FAttrs[I].NameP);
    end;
    if FBindingCount = Length(FBindings) then
      SetLength(FBindings, 2 * FBindingCount);
    FBindings[FBindingCount].PrefixP := PrefixP;
    FBindings[FBindingCount].PrefixLen := PrefixLen;
    FBindings[FBindingCount].Uri := Uri;
    Inc(FBindingCount);
  end;
  { 2. element name }
  if E^.ColonPos >= 0 then
  begin
    if SpanEqualsAscii(E^.NameP, E^.ColonPos, 'xmlns') then
      Fail(xecNamespace, 'Element names must not have the prefix "xmlns"', E^.NameP);
    B := FindBinding(E^.NameP, E^.ColonPos);
    if B < 0 then
      Fail(xecNamespace, 'Undeclared namespace prefix "' + LandrixXmlEscapeForMessage(
        LandrixXmlSpanToUtf8(MakeSpan(E^.NameP, E^.ColonPos)), 40) + '"', E^.NameP);
  end
  else
    B := FindBinding(E^.NameP, 0);
  if B >= 0 then
  begin
    E^.NsP := PAnsiChar(FBindings[B].Uri);
    E^.NsLen := Length(FBindings[B].Uri);
  end
  else
  begin
    E^.NsP := nil;
    E^.NsLen := 0;
  end;
  { 3. attribute names }
  for I := 0 to FAttrCount - 1 do
  begin
    if FAttrs[I].IsNsDecl then
    begin
      FAttrs[I].NsP := LandrixXmlNamespaceXmlns;
      FAttrs[I].NsLen := Length(LandrixXmlNamespaceXmlns);
    end
    else if FAttrs[I].ColonPos >= 0 then
    begin
      B := FindBinding(FAttrs[I].NameP, FAttrs[I].ColonPos);
      if B < 0 then
        Fail(xecNamespace, 'Undeclared namespace prefix "' + LandrixXmlEscapeForMessage(
          LandrixXmlSpanToUtf8(MakeSpan(FAttrs[I].NameP, FAttrs[I].ColonPos)), 40) + '"',
          FAttrs[I].NameP);
      FAttrs[I].NsP := PAnsiChar(FBindings[B].Uri);
      FAttrs[I].NsLen := Length(FBindings[B].Uri);
    end
    else
    begin
      FAttrs[I].NsP := nil;
      FAttrs[I].NsLen := 0;
    end;
  end;
  CheckDuplicates(True);
end;

procedure TLandrixXmlReader.ReadStartTag;
var
  P, NameP, ValueStart: PAnsiChar;
  NameLen, I: Integer;
  HadSpace, NeedsDecode: Boolean;
  Quote: AnsiChar;
  E: ^TLandrixXmlReaderElement;
begin
  P := FCur + 1;
  NameP := P;
  NameLen := ScanName(P);
  if FElemCount >= FMaxDepth then
    Fail(xecLimit, 'Maximum nesting depth of ' + IntToStr(FMaxDepth) + ' exceeded', FCur);
  if FElemCount = Length(FElems) then
  begin
    if FElemCount = 0 then
      SetLength(FElems, 32)
    else
      SetLength(FElems, 2 * FElemCount);
  end;
  E := @FElems[FElemCount];
  E^.NameP := NameP;
  E^.NameLen := NameLen;
  E^.ColonPos := CheckQName(NameP, NameLen);
  E^.BindingTop := FBindingCount;
  FAttrCount := 0;
  while True do
  begin
    HadSpace := False;
    while P^ in SpaceChars do
    begin
      Inc(P);
      HadSpace := True;
    end;
    if P^ = '>' then
    begin
      Inc(P);
      Break;
    end;
    if (P^ = '/') and (P[1] = '>') then
    begin
      Inc(P, 2);
      FIsEmpty := True;
      Break;
    end;
    if P >= FEnd then
      Fail(xecSyntax, 'Unexpected end of input in start tag', P);
    if not HadSpace then
      Fail(xecSyntax, 'White space or end of tag expected', P);
    { attribute }
    if FAttrCount = Length(FAttrs) then
    begin
      if FAttrCount = 0 then
        SetLength(FAttrs, 16)
      else
        SetLength(FAttrs, 2 * FAttrCount);
    end;
    FAttrs[FAttrCount].NameP := P;
    FAttrs[FAttrCount].NameLen := ScanName(P);
    FAttrs[FAttrCount].ColonPos := CheckQName(FAttrs[FAttrCount].NameP, FAttrs[FAttrCount].NameLen);
    FAttrs[FAttrCount].IsNsDecl := False;
    while P^ in SpaceChars do
      Inc(P);
    if P^ <> '=' then
      Fail(xecSyntax, '"=" expected after attribute name', P);
    Inc(P);
    while P^ in SpaceChars do
      Inc(P);
    if (P^ <> '"') and (P^ <> '''') then
      Fail(xecSyntax, 'Quoted attribute value expected', P);
    Quote := P^;
    Inc(P);
    ValueStart := P;
    NeedsDecode := False;
    while P^ <> Quote do
    begin
      case P^ of
        '<':
          Fail(xecSyntax, '"<" is not allowed in attribute values', P);
        '&', #9, #10, #13:
          NeedsDecode := True;
        #0:
          if P >= FEnd then
            Fail(xecSyntax, 'Unterminated attribute value', ValueStart - 1)
          else
            CheckSpecialChar(P);
      else
        if (Ord(P^) < $20) or (P^ = #$EF) then
          CheckSpecialChar(P);
      end;
      Inc(P);
    end;
    if NeedsDecode then
    begin
      FAttrs[FAttrCount].ValueOfs := FScratch.Size;
      DecodeInto(ValueStart, P, dmAttribute);
      FAttrs[FAttrCount].ValueLen := FScratch.Size - FAttrs[FAttrCount].ValueOfs;
    end
    else
    begin
      FAttrs[FAttrCount].ValueOfs := -1;
      FAttrs[FAttrCount].ValueP := ValueStart;
      FAttrs[FAttrCount].ValueLen := Integer(P - ValueStart);
    end;
    Inc(P); { closing quote }
    Inc(FAttrCount);
  end;
  FCur := P;
  { the scratch buffer is complete: materialize decoded value pointers }
  for I := 0 to FAttrCount - 1 do
    if FAttrs[I].ValueOfs >= 0 then
      FAttrs[I].ValueP := FScratch.Data + FAttrs[I].ValueOfs;
  CheckDuplicates(False);
  Inc(FElemCount);
  ProcessNamespaces;
  E := @FElems[FElemCount - 1];
  FToken := xttStartElement;
  FDepth := FElemCount - 1;
  FNameP := E^.NameP;
  FNameLen := E^.NameLen;
  FColonPos := E^.ColonPos;
  FNsP := E^.NsP;
  FNsLen := E^.NsLen;
  if FIsEmpty then
    FPendingEnd := True;
end;

procedure TLandrixXmlReader.SetEndToken;
var
  E: ^TLandrixXmlReaderElement;
begin
  E := @FElems[FElemCount - 1];
  FToken := xttEndElement;
  FDepth := FElemCount - 1;
  FNameP := E^.NameP;
  FNameLen := E^.NameLen;
  FColonPos := E^.ColonPos;
  FNsP := E^.NsP;
  FNsLen := E^.NsLen;
  FPendingPop := True;
end;

procedure TLandrixXmlReader.ReadEndTag;
var
  P, NameP: PAnsiChar;
  NameLen: Integer;
  E: ^TLandrixXmlReaderElement;
begin
  P := FCur + 2;
  NameP := P;
  NameLen := ScanName(P);
  while P^ in SpaceChars do
    Inc(P);
  if P^ <> '>' then
    Fail(xecSyntax, '">" expected at end of end tag', P);
  E := @FElems[FElemCount - 1];
  if not SameBytes(NameP, NameLen, E^.NameP, E^.NameLen) then
    Fail(xecSyntax, 'End tag "' + LandrixXmlEscapeForMessage(
      LandrixXmlSpanToUtf8(MakeSpan(NameP, NameLen)), 60) + '" does not match start tag "' +
      LandrixXmlEscapeForMessage(LandrixXmlSpanToUtf8(MakeSpan(E^.NameP, E^.NameLen)), 60) +
      '"', NameP);
  FCur := P + 1;
  SetEndToken;
end;

procedure TLandrixXmlReader.PopElement;
var
  I: Integer;
begin
  Dec(FElemCount);
  for I := FElems[FElemCount].BindingTop to FBindingCount - 1 do
    FBindings[I].Uri := '';
  FBindingCount := FElems[FElemCount].BindingTop;
  if FElemCount = 0 then
    FState := rsEpilog;
end;

function TLandrixXmlReader.ReadNext: Boolean;
var
  P: PAnsiChar;
begin
  Result := True;
  if FState in [rsProlog, rsEpilog] then
  begin
    P := FCur;
    while P^ in SpaceChars do
      Inc(P);
    FCur := P;
    FTokenStart := P;
    FDepth := 0;
    if P >= FEnd then
    begin
      if FState = rsProlog then
        Fail(xecSyntax, 'The document has no root element', P);
      FState := rsEnd;
      FToken := xttEndOfDocument;
      Result := False;
      Exit;
    end;
    if P^ <> '<' then
    begin
      if FState = rsProlog then
        Fail(xecSyntax, 'Text is not allowed before the root element', P)
      else
        Fail(xecSyntax, 'Text is not allowed after the root element', P);
    end;
    case P[1] of
      '?':
        ReadProcessingInstruction;
      '!':
        if (P[2] = '-') and (P[3] = '-') then
          ReadComment
        else if (FState = rsProlog) and not FHasDocType and
          SpanEqualsAscii(P, 9, '<!DOCTYPE') then
          ReadDocType
        else
          Fail(xecSyntax, 'Unexpected markup outside the root element', P);
      '/':
        Fail(xecSyntax, 'End tag without start tag', P);
    else
      if FState = rsEpilog then
        Fail(xecSyntax, 'Only one root element is allowed', P);
      FState := rsContent;
      ReadStartTag;
    end;
    Exit;
  end;

  { content }
  P := FCur;
  FTokenStart := P;
  FDepth := FElemCount;
  if P >= FEnd then
    Fail(xecSyntax, 'Unexpected end of input: element "' + LandrixXmlEscapeForMessage(
      LandrixXmlSpanToUtf8(MakeSpan(FElems[FElemCount - 1].NameP,
      FElems[FElemCount - 1].NameLen)), 60) + '" is not closed', P);
  if P^ <> '<' then
  begin
    ReadText;
    Exit;
  end;
  case P[1] of
    '/':
      ReadEndTag;
    '?':
      ReadProcessingInstruction;
    '!':
      if (P[2] = '-') and (P[3] = '-') then
        ReadComment
      else if SpanEqualsAscii(P, 9, '<![CDATA[') then
        ReadCData
      else
        Fail(xecSyntax, 'Unexpected markup in content', P);
  else
    ReadStartTag;
  end;
end;

function TLandrixXmlReader.Read: Boolean;
begin
  CheckLiveState;
  if FState = rsEnd then
  begin
    FToken := xttEndOfDocument;
    Result := False;
    Exit;
  end;
  { reset per-token data }
  FScratch.Clear;
  FAttrCount := 0;
  FIsEmpty := False;
  FIsWhitespace := False;
  FNameP := nil;
  FNameLen := 0;
  FColonPos := -1;
  FNsP := nil;
  FNsLen := 0;
  FValueP := nil;
  FValueLen := 0;
  FValueOfs := -1;
  try
    if FPendingPop then
    begin
      FPendingPop := False;
      PopElement;
    end;
    if FPendingEnd then
    begin
      FPendingEnd := False;
      FIsEmpty := True; { also on the end token of <x/> }
      SetEndToken;
      Result := True;
      Exit;
    end;
    if FState = rsInitial then
    begin
      FState := rsProlog;
      ReadXmlDeclaration;
    end;
    Result := ReadNext;
    if FValueOfs >= 0 then
      FValueP := FScratch.Data + FValueOfs;
  except
    FState := rsError;
    raise;
  end;
end;

procedure TLandrixXmlReader.Skip;
var
  D: Integer;
begin
  if (FToken <> xttStartElement) then
    Exit;
  D := FDepth;
  while Read do
    if (FToken = xttEndElement) and (FDepth = D) then
      Exit;
end;

procedure TLandrixXmlReader.Run(Handler: TLandrixXmlHandler);
begin
  while Read do
    case FToken of
      xttStartElement: Handler.StartElement(Self);
      xttEndElement: Handler.EndElement(Self);
      xttText: Handler.Text(Self);
      xttCData: Handler.CData(Self);
      xttComment: Handler.Comment(Self);
      xttProcessingInstruction: Handler.ProcessingInstruction(Self);
      xttDocumentType: Handler.DocumentType(Self);
    else
      { xttNone and xttEndOfDocument do not occur inside the loop }
    end;
  Handler.EndDocument(Self);
end;

{ --- accessors --------------------------------------------------------------- }

function TLandrixXmlReader.GetValueSpan: TLandrixXmlSpan;
begin
  Result := MakeSpan(FValueP, FValueLen);
end;

function TLandrixXmlReader.GetNameSpan: TLandrixXmlSpan;
begin
  Result := MakeSpan(FNameP, FNameLen);
end;

function TLandrixXmlReader.GetPrefixSpan: TLandrixXmlSpan;
begin
  if FColonPos >= 0 then
    Result := MakeSpan(FNameP, FColonPos)
  else
    Result := MakeSpan(FNameP, 0);
end;

function TLandrixXmlReader.GetLocalNameSpan: TLandrixXmlSpan;
begin
  Result := MakeSpan(FNameP + FColonPos + 1, FNameLen - FColonPos - 1);
end;

function TLandrixXmlReader.GetNamespaceUriSpan: TLandrixXmlSpan;
begin
  Result := MakeSpan(FNsP, FNsLen);
end;

function TLandrixXmlReader.NameUtf8: TLandrixXmlUtf8;
begin
  Result := LandrixXmlSpanToUtf8(GetNameSpan);
end;

function TLandrixXmlReader.PrefixUtf8: TLandrixXmlUtf8;
begin
  Result := LandrixXmlSpanToUtf8(GetPrefixSpan);
end;

function TLandrixXmlReader.LocalNameUtf8: TLandrixXmlUtf8;
begin
  Result := LandrixXmlSpanToUtf8(GetLocalNameSpan);
end;

function TLandrixXmlReader.NamespaceUriUtf8: TLandrixXmlUtf8;
begin
  Result := LandrixXmlSpanToUtf8(GetNamespaceUriSpan);
end;

function TLandrixXmlReader.ValueUtf8: TLandrixXmlUtf8;
begin
  Result := LandrixXmlSpanToUtf8(GetValueSpan);
end;

function TLandrixXmlReader.LocalNameW: TLandrixXmlWide;
begin
  Result := LandrixXmlUtf8ToWide(LocalNameUtf8);
end;

function TLandrixXmlReader.NamespaceUriW: TLandrixXmlWide;
begin
  Result := LandrixXmlUtf8ToWide(NamespaceUriUtf8);
end;

function TLandrixXmlReader.ValueW: TLandrixXmlWide;
begin
  Result := LandrixXmlUtf8ToWide(ValueUtf8);
end;

function TLandrixXmlReader.Name: string;
begin
  Result := LandrixXmlUtf8ToString(NameUtf8);
end;

function TLandrixXmlReader.LocalName: string;
begin
  Result := LandrixXmlUtf8ToString(LocalNameUtf8);
end;

function TLandrixXmlReader.NamespaceUri: string;
begin
  Result := LandrixXmlUtf8ToString(NamespaceUriUtf8);
end;

function TLandrixXmlReader.Value: string;
begin
  Result := LandrixXmlUtf8ToString(ValueUtf8);
end;

procedure TLandrixXmlReader.CheckAttrIndex(Index: Integer);
begin
  if (Index < 0) or (Index >= FAttrCount) then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument,
      'Attribute index out of range: ' + IntToStr(Index));
end;

function TLandrixXmlReader.AttributeNameSpan(Index: Integer): TLandrixXmlSpan;
begin
  CheckAttrIndex(Index);
  Result := MakeSpan(FAttrs[Index].NameP, FAttrs[Index].NameLen);
end;

function TLandrixXmlReader.AttributePrefixSpan(Index: Integer): TLandrixXmlSpan;
begin
  CheckAttrIndex(Index);
  if FAttrs[Index].ColonPos >= 0 then
    Result := MakeSpan(FAttrs[Index].NameP, FAttrs[Index].ColonPos)
  else
    Result := MakeSpan(FAttrs[Index].NameP, 0);
end;

function TLandrixXmlReader.AttributeLocalNameSpan(Index: Integer): TLandrixXmlSpan;
begin
  CheckAttrIndex(Index);
  Result := MakeSpan(FAttrs[Index].NameP + FAttrs[Index].ColonPos + 1,
    FAttrs[Index].NameLen - FAttrs[Index].ColonPos - 1);
end;

function TLandrixXmlReader.AttributeNamespaceUriSpan(Index: Integer): TLandrixXmlSpan;
begin
  CheckAttrIndex(Index);
  Result := MakeSpan(FAttrs[Index].NsP, FAttrs[Index].NsLen);
end;

function TLandrixXmlReader.AttributeValueSpan(Index: Integer): TLandrixXmlSpan;
begin
  CheckAttrIndex(Index);
  Result := MakeSpan(FAttrs[Index].ValueP, FAttrs[Index].ValueLen);
end;

function TLandrixXmlReader.AttributeNameUtf8(Index: Integer): TLandrixXmlUtf8;
begin
  Result := LandrixXmlSpanToUtf8(AttributeNameSpan(Index));
end;

function TLandrixXmlReader.AttributeLocalNameUtf8(Index: Integer): TLandrixXmlUtf8;
begin
  Result := LandrixXmlSpanToUtf8(AttributeLocalNameSpan(Index));
end;

function TLandrixXmlReader.AttributeNamespaceUriUtf8(Index: Integer): TLandrixXmlUtf8;
begin
  Result := LandrixXmlSpanToUtf8(AttributeNamespaceUriSpan(Index));
end;

function TLandrixXmlReader.AttributeValueUtf8(Index: Integer): TLandrixXmlUtf8;
begin
  Result := LandrixXmlSpanToUtf8(AttributeValueSpan(Index));
end;

function TLandrixXmlReader.AttributeValueW(Index: Integer): TLandrixXmlWide;
begin
  Result := LandrixXmlUtf8ToWide(AttributeValueUtf8(Index));
end;

function TLandrixXmlReader.AttributeValue(Index: Integer): string;
begin
  Result := LandrixXmlUtf8ToString(AttributeValueUtf8(Index));
end;

function TLandrixXmlReader.IsNamespaceDeclaration(Index: Integer): Boolean;
begin
  CheckAttrIndex(Index);
  Result := FAttrs[Index].IsNsDecl;
end;

function TLandrixXmlReader.AttributeIndex(const NamespaceUri,
  LocalName: TLandrixXmlUtf8): Integer;
var
  I: Integer;
begin
  for I := 0 to FAttrCount - 1 do
    if SameBytes(FAttrs[I].NsP, FAttrs[I].NsLen, PAnsiChar(NamespaceUri), Length(NamespaceUri)) and
      SameBytes(FAttrs[I].NameP + FAttrs[I].ColonPos + 1, FAttrs[I].NameLen - FAttrs[I].ColonPos - 1,
        PAnsiChar(LocalName), Length(LocalName)) then
    begin
      Result := I;
      Exit;
    end;
  Result := -1;
end;

function TLandrixXmlReader.LookupNamespace(const Prefix: TLandrixXmlUtf8;
  out Uri: TLandrixXmlUtf8): Boolean;
var
  B: Integer;
begin
  if Prefix = 'xmlns' then
  begin
    { bound by definition (Namespaces in XML 1.0, section 3) }
    Uri := LandrixXmlNamespaceXmlns;
    Result := True;
    Exit;
  end;
  B := FindBinding(PAnsiChar(Prefix), Length(Prefix));
  Result := B >= 0;
  if Result then
    Uri := FBindings[B].Uri
  else
    Uri := '';
  { an empty default namespace means "no default namespace" }
  if Result and (Length(Prefix) = 0) and (Uri = '') then
    Result := False;
end;

end.
