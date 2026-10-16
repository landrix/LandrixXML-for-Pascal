{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Streaming writer for well-formed XML 1.0 with namespaces. Output is
  always UTF-8.

  Usage:
    Writer := TLandrixXmlWriter.CreateFile('invoice.xml');
    try
      Writer.Indent := True;
      Writer.StartElementNs(UblNs, '', 'Invoice');
      Writer.DeclareNamespace('cbc', CbcNs);
      Writer.Element('cbc:ID', InvoiceNumber);
      Writer.StartElement('cbc:PayableAmount');
      Writer.Attribute('currencyID', 'EUR');
      Writer.Text('119.00');
      Writer.EndElement;
      Writer.EndElement;
      Writer.EndDocument;
    finally
      Writer.Free;
    end;

  Rules (see PLAN.md decision log):
  - The XML declaration <?xml version="1.0" encoding="UTF-8"?> is written
    automatically before the first output unless WriteDeclaration is
    False. Options cannot be changed once output has started.
  - Every call is atomic: a call that raises leaves the output and the
    writer state unchanged, and the writer stays usable. Only a failing
    target stream makes it unusable (until Clear). Checks that need the
    complete start tag (namespace prefixes, duplicate attributes after
    namespace resolution) run when the start tag is closed, i.e. in the
    next call that writes content or ends the element.
  - Names and namespace URIs are passed as UTF-8. Values come in three
    variants: native string (Text), UTF-8 (TextUtf8) and UTF-16 (TextW).
  - Values that cannot be written so that a parser reads them back
    unchanged are rejected: characters outside XML 1.0 Char
    (xecInvalidChar), malformed UTF-8/UTF-16 (xecInvalidUnicode), "]]>" or
    CR in CDATA, "--" or CR in comments, "?>" or CR in processing
    instructions (xecWrite). In text, CR is written as &#13;; in attribute
    values TAB, LF and CR are written as character references.
  - EndDocument never closes open elements; open elements or a missing
    root element are errors.
  - Indentation (Indent = True) is never added inside elements started
    with Mixed = True, below xml:space="preserve", or inside an element
    after text was written into it. Leaf elements stay on one line. Text
    after indented child nodes is rejected (xecWrite) instead of silently
    changing the content: start such elements with Mixed = True.
  - Destroy never flushes: call EndDocument (or Flush) before freeing a
    stream writer. }

unit LandrixXmlWriter;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  Classes,
  LandrixXmlBase;

type
  { Line break used for indentation and after the XML declaration. Line
    breaks inside values are never changed. }
  TLandrixXmlLineBreak = (xlbLF, xlbCRLF);

  { The standalone pseudo-attribute of the XML declaration. }
  TLandrixXmlStandalone = (xsaOmit, xsaYes, xsaNo);

  { Internal bookkeeping records of TLandrixXmlWriter. }
  TLandrixXmlWriterElement = record
    QName: TLandrixXmlUtf8;
    ColonPos: Integer;          { -1 = no prefix }
    RequiredUri: TLandrixXmlUtf8;
    HasRequiredUri: Boolean;    { started with StartElementNs }
    BindingTop: Integer;        { binding count before this element }
    OwnMixed: Boolean;          { Mixed parameter }
    InheritedMixed: Boolean;    { an ancestor was started with Mixed = True }
    InheritedPreserve: Boolean; { xml:space="preserve" in scope from above }
    Space: Integer;             { xml:space: 0 none, 1 preserve, 2 default }
    Mixed: Boolean;             { effective: no indentation inside }
    HasText: Boolean;
    HasChildren: Boolean;
  end;

  TLandrixXmlWriterAttr = record
    QName: TLandrixXmlUtf8;
    ColonPos: Integer;
    RequiredUri: TLandrixXmlUtf8;
    HasRequiredUri: Boolean;
    IsNsDecl: Boolean;
    Uri: TLandrixXmlUtf8;       { resolved when the start tag closes }
  end;

  TLandrixXmlWriterBinding = record
    Prefix: TLandrixXmlUtf8;
    Uri: TLandrixXmlUtf8;
  end;

  TLandrixXmlWriterSnapshot = record
    BufSize: Integer;
    Flushed: Int64;
    ElemCount: Integer;
    AttrCount: Integer;
    BindingCount: Integer;
    TopCount: Integer;
    InStartTag: Boolean;
    Started: Boolean;
    RootDone: Boolean;
    HasDocType: Boolean;
    Top: TLandrixXmlWriterElement;
  end;

  TLandrixXmlWriter = class
  private
    FBuf: TLandrixXmlBuffer;
    FStream: TStream;
    FOwnsStream: Boolean;
    FFlushed: Int64;
    FElems: array of TLandrixXmlWriterElement;
    FElemCount: Integer;
    FAttrs: array of TLandrixXmlWriterAttr;
    FAttrCount: Integer;
    FBindings: array of TLandrixXmlWriterBinding;
    FBindingCount: Integer;
    FHash: array of Integer;
    FHashCount: Integer;        { attributes entered in FHash; -1 = stale }
    FChunk: array of Byte;
    FInStartTag: Boolean;
    FStarted: Boolean;
    FRootDone: Boolean;
    FHasDocType: Boolean;
    FFinished: Boolean;
    FBroken: Boolean;
    FTopCount: Integer;
    FWriteDeclaration: Boolean;
    FWriteBom: Boolean;
    FStandalone: TLandrixXmlStandalone;
    FIndent: Boolean;
    FIndentString: TLandrixXmlUtf8;
    FLineBreak: TLandrixXmlLineBreak;
    procedure Init;
    procedure CheckOptionChange;
    procedure SetWriteDeclaration(Value: Boolean);
    procedure SetWriteBom(Value: Boolean);
    procedure SetStandalone(Value: TLandrixXmlStandalone);
    procedure SetIndent(Value: Boolean);
    procedure SetIndentString(const Value: TLandrixXmlUtf8);
    procedure SetLineBreak(Value: TLandrixXmlLineBreak);
    function GetBytesWritten: Int64;
    function ElementPath: string;
    procedure Fail(Code: TLandrixXmlErrorCode; const Msg: string);
    procedure FailAt(Code: TLandrixXmlErrorCode; const Msg: string; Offset: Integer);
    procedure CheckUsable;
    procedure CheckResult;
    procedure TakeSnapshot(out S: TLandrixXmlWriterSnapshot);
    procedure Rollback(const S: TLandrixXmlWriterSnapshot);
    procedure FlushBuffer;
    procedure AfterCall;
    procedure AppendLit(const S: AnsiString);
    procedure AppendStr(const S: TLandrixXmlUtf8);
    procedure AppendLineBreak;
    procedure WriteIndent(Level: Integer);
    procedure EnsureStarted;
    procedure BeforeTopLevel;
    procedure BeforeChild;
    procedure BeforeText;
    procedure Emit(P: PAnsiChar; Len: Integer; Mode: Integer; const What: string);
    procedure CheckValue(P: PAnsiChar; Len: Integer; const What: string);
    function CheckQName(const QName: TLandrixXmlUtf8; const What: string): Integer;
    procedure CheckNcName(const Name: TLandrixXmlUtf8; const What: string);
    procedure CheckNsArgs(const NamespaceUri, Prefix, LocalName: TLandrixXmlUtf8;
      IsAttribute: Boolean);
    function FindBinding(const Prefix: TLandrixXmlUtf8): Integer;
    function FindAttr(const QName: TLandrixXmlUtf8): Integer;
    procedure RebuildHash;
    procedure HashAdded;
    function UsesPrefixLexically(const Prefix: TLandrixXmlUtf8): Boolean;
    procedure Require(const Prefix, Uri: TLandrixXmlUtf8);
    procedure CheckExpandedDuplicates;
    procedure CloseStartTag(Empty: Boolean);
    procedure StartElementCore(const QName: TLandrixXmlUtf8; ColonPos: Integer;
      const RequiredUri: TLandrixXmlUtf8; HasRequiredUri, Mixed: Boolean);
    procedure EndElementCore;
    procedure DeclareCore(const Prefix, Uri: TLandrixXmlUtf8);
    procedure AttributeCore(const QName: TLandrixXmlUtf8; ColonPos: Integer;
      const RequiredUri: TLandrixXmlUtf8; HasRequiredUri: Boolean;
      const Value: TLandrixXmlUtf8);
    procedure DoStartElement(const QName: TLandrixXmlUtf8; Mixed: Boolean);
    procedure DoStartElementNs(const NamespaceUri, Prefix, LocalName: TLandrixXmlUtf8;
      Mixed: Boolean);
    procedure DoAttribute(const QName, Value: TLandrixXmlUtf8);
    procedure DoAttributeNs(const NamespaceUri, Prefix, LocalName, Value: TLandrixXmlUtf8);
    procedure DoElement(const QName, Value: TLandrixXmlUtf8);
    procedure DoElementNs(const NamespaceUri, Prefix, LocalName, Value: TLandrixXmlUtf8);
    procedure DoText(const Value: TLandrixXmlUtf8);
    procedure DoCData(const Value: TLandrixXmlUtf8);
    procedure DoComment(const Value: TLandrixXmlUtf8);
    procedure DoProcessingInstruction(const Target, Data: TLandrixXmlUtf8);
  public
    { Writes into memory; get the result with AsUtf8, AsW, AsString,
      SaveToStream or SaveToFile after EndDocument. }
    constructor Create; overload;
    { Writes to Stream (at its current position); the stream is not owned. }
    constructor Create(Stream: TStream); overload;
    { Creates (overwrites) the file and writes to it; the file is closed
      when the writer is freed. }
    constructor CreateFile(const FileName: string);
    { Frees the writer without flushing pending output. }
    destructor Destroy; override;

    { Discards all state and buffered output so a new document can be
      written (to memory, or appended to the same stream). Options are kept. }
    procedure Clear;
    { Writes buffered output to the target stream (no-op in memory mode). }
    procedure Flush;

    { Writes BOM and declaration now (otherwise done before the first
      output). Raises if output has already started. }
    procedure StartDocument;
    { Checks that the root element was written and closed and flushes the
      output. Afterwards only Clear, Flush and the result methods work. }
    procedure EndDocument;

    { QName is "local" or "prefix:local"; the prefix must be declared when
      the start tag closes (on this element or an ancestor). Mixed = True
      disables indentation in this subtree (mixed content). }
    procedure StartElement(const QName: TLandrixXmlUtf8; Mixed: Boolean = False);
    { Like StartElement, but guarantees the namespace: declares Prefix
      (or the default namespace when Prefix = '') on this element unless it
      is already bound to NamespaceUri. NamespaceUri = '' with Prefix = ''
      means "no namespace" (writes xmlns="" when a default namespace is in
      scope). }
    procedure StartElementNs(const NamespaceUri, Prefix, LocalName: TLandrixXmlUtf8;
      Mixed: Boolean = False);
    { Closes the current element; writes <x/> when it is empty. }
    procedure EndElement;

    { Declares a namespace on the current start tag (Prefix = '' for the
      default namespace). Writing an xmlns or xmlns:p attribute has the
      same effect. }
    procedure DeclareNamespace(const Prefix, NamespaceUri: TLandrixXmlUtf8);

    { Attributes of the current start tag. Unprefixed attributes have no
      namespace. }
    procedure Attribute(const QName: TLandrixXmlUtf8; const Value: string);
    procedure AttributeUtf8(const QName, Value: TLandrixXmlUtf8);
    procedure AttributeW(const QName: TLandrixXmlUtf8; const Value: TLandrixXmlWide);
    { Namespaced attribute: Prefix is required when NamespaceUri <> '' and
      declared automatically when needed. }
    procedure AttributeNs(const NamespaceUri, Prefix, LocalName: TLandrixXmlUtf8;
      const Value: string);
    procedure AttributeNsUtf8(const NamespaceUri, Prefix, LocalName, Value: TLandrixXmlUtf8);
    procedure AttributeNsW(const NamespaceUri, Prefix, LocalName: TLandrixXmlUtf8;
      const Value: TLandrixXmlWide);

    { Complete leaf element <q>Value</q>; <q/> when Value is empty. }
    procedure Element(const QName: TLandrixXmlUtf8; const Value: string);
    procedure ElementUtf8(const QName, Value: TLandrixXmlUtf8);
    procedure ElementW(const QName: TLandrixXmlUtf8; const Value: TLandrixXmlWide);
    procedure ElementNs(const NamespaceUri, Prefix, LocalName: TLandrixXmlUtf8;
      const Value: string);
    procedure ElementNsUtf8(const NamespaceUri, Prefix, LocalName, Value: TLandrixXmlUtf8);
    procedure ElementNsW(const NamespaceUri, Prefix, LocalName: TLandrixXmlUtf8;
      const Value: TLandrixXmlWide);

    { Character data inside an element. Outside the root element only
      white space is allowed (written literally). }
    procedure Text(const Value: string);
    procedure TextUtf8(const Value: TLandrixXmlUtf8);
    procedure TextW(const Value: TLandrixXmlWide);
    procedure CData(const Value: string);
    procedure CDataUtf8(const Value: TLandrixXmlUtf8);
    procedure CDataW(const Value: TLandrixXmlWide);
    procedure Comment(const Value: string);
    procedure CommentUtf8(const Value: TLandrixXmlUtf8);
    procedure CommentW(const Value: TLandrixXmlWide);
    procedure ProcessingInstruction(const Target: TLandrixXmlUtf8; const Data: string);
    procedure ProcessingInstructionUtf8(const Target, Data: TLandrixXmlUtf8);
    procedure ProcessingInstructionW(const Target: TLandrixXmlUtf8;
      const Data: TLandrixXmlWide);
    { <!DOCTYPE Name Content>, before the root element only. Content is
      everything after the name, as reported by the reader (starting with
      white space, e.g. ' SYSTEM "a.dtd"'); it is checked for balanced
      quotes, brackets, comments and PIs, not for DTD validity. }
    procedure DocumentType(const Name, Content: TLandrixXmlUtf8);

    { Base64 (RFC 4648, no line breaks) of Size bytes as text content.
      Each call writes one complete value including padding. }
    procedure Base64(const Buffer; Size: Integer);
    { Base64 of Count bytes (-1 = up to the end) read from Stream in
      chunks; in stream mode the output is flushed in between, so memory
      use stays constant. If the
      output was already flushed when an error occurs, the writer becomes
      unusable (the output is incomplete). }
    procedure Base64FromStream(Stream: TStream; Count: Int64 = -1);

    { Results in memory mode, after EndDocument. AsW and AsString decode the
      UTF-8 output (a BOM becomes U+FEFF); AsString is lossy on Delphi
      6-2007 for characters outside the system code page. }
    function AsUtf8: TLandrixXmlUtf8;
    function AsW: TLandrixXmlWide;
    function AsString: string;
    procedure SaveToStream(Stream: TStream);
    procedure SaveToFile(const FileName: string);

    { Number of open elements. }
    property Depth: Integer read FElemCount;
    { Bytes produced so far (flushed and buffered). }
    property BytesWritten: Int64 read GetBytesWritten;

    property WriteDeclaration: Boolean read FWriteDeclaration write SetWriteDeclaration;
    property WriteBom: Boolean read FWriteBom write SetWriteBom;
    property Standalone: TLandrixXmlStandalone read FStandalone write SetStandalone;
    property Indent: Boolean read FIndent write SetIndent;
    { Spaces and TABs only; default two spaces. }
    property IndentString: TLandrixXmlUtf8 read FIndentString write SetIndentString;
    property LineBreak: TLandrixXmlLineBreak read FLineBreak write SetLineBreak;
  end;

implementation

const
  { Emit modes }
  emText = 0;
  emAttribute = 1;
  emRaw = 2;      { validation only (CDATA, comments, PIs, DOCTYPE) }

  FlushThreshold = 65536;
  { input chunk for Base64FromStream, a multiple of 3 }
  Base64Chunk = 49152;
  { duplicate check: below this count a quadratic check is cheaper }
  HashThreshold = 12;

{ --- string helpers --------------------------------------------------------- }

function SubUtf8(const S: TLandrixXmlUtf8; Start, Len: Integer): TLandrixXmlUtf8;
begin
  Result := '';
  if Len > 0 then
  begin
    SetLength(Result, Len);
    Move(PAnsiChar(S)[Start], PAnsiChar(Result)^, Len);
  end;
end;

function JoinQName(const Prefix, LocalName: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  P: PAnsiChar;
begin
  if Prefix = '' then
  begin
    Result := LocalName;
    Exit;
  end;
  SetLength(Result, Length(Prefix) + 1 + Length(LocalName));
  P := PAnsiChar(Result);
  Move(PAnsiChar(Prefix)^, P^, Length(Prefix));
  P[Length(Prefix)] := ':';
  if LocalName <> '' then
    Move(PAnsiChar(LocalName)^, P[Length(Prefix) + 1], Length(LocalName));
end;

function SameAscii(const S: TLandrixXmlUtf8; const A: AnsiString): Boolean;
var
  I: Integer;
begin
  Result := Length(S) = Length(A);
  I := 1;
  while Result and (I <= Length(S)) do
  begin
    Result := S[I] = A[I];
    Inc(I);
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

{ Position of the first occurrence of the ASCII sequence A in P/Len, or -1. }
function FindSeq(P: PAnsiChar; Len: Integer; const A: AnsiString): Integer;
var
  I, J: Integer;
  Match: Boolean;
begin
  for I := 0 to Len - Length(A) do
  begin
    Match := True;
    J := 1;
    while Match and (J <= Length(A)) do
    begin
      Match := P[I + J - 1] = A[J];
      Inc(J);
    end;
    if Match then
    begin
      Result := I;
      Exit;
    end;
  end;
  Result := -1;
end;

function IsSpace(C: AnsiChar): Boolean;
begin
  Result := (C = ' ') or (C = #9) or (C = #10) or (C = #13);
end;

{ --- TLandrixXmlWriter: setup --------------------------------------------- }

constructor TLandrixXmlWriter.Create;
begin
  inherited Create;
  Init;
end;

constructor TLandrixXmlWriter.Create(Stream: TStream);
begin
  inherited Create;
  if Stream = nil then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'Stream must not be nil');
  Init;
  FStream := Stream;
end;

constructor TLandrixXmlWriter.CreateFile(const FileName: string);
begin
  inherited Create;
  Init;
  FStream := TFileStream.Create(FileName, fmCreate);
  FOwnsStream := True;
end;

destructor TLandrixXmlWriter.Destroy;
begin
  if FOwnsStream then
    FStream.Free;
  FBuf.Free;
  inherited Destroy;
end;

procedure TLandrixXmlWriter.Init;
begin
  FBuf := TLandrixXmlBuffer.Create;
  FWriteDeclaration := True;
  FIndentString := '  ';
  FLineBreak := xlbLF;
  Clear;
end;

procedure TLandrixXmlWriter.Clear;
begin
  FBuf.Clear;
  FElemCount := 0;
  FAttrCount := 0;
  if Length(FBindings) = 0 then
    SetLength(FBindings, 16);
  FBindings[0].Prefix := 'xml';
  FBindings[0].Uri := LandrixXmlNamespaceXml;
  FBindingCount := 1;
  FHashCount := -1;
  FInStartTag := False;
  FStarted := False;
  FRootDone := False;
  FHasDocType := False;
  FFinished := False;
  FBroken := False;
  FTopCount := 0;
  FFlushed := 0;
end;

procedure TLandrixXmlWriter.CheckOptionChange;
begin
  if FStarted then
    raise ELandrixXmlError.CreateCode(xecInvalidOperation,
      'Writer options cannot be changed after output has started');
end;

procedure TLandrixXmlWriter.SetWriteDeclaration(Value: Boolean);
begin
  CheckOptionChange;
  FWriteDeclaration := Value;
end;

procedure TLandrixXmlWriter.SetWriteBom(Value: Boolean);
begin
  CheckOptionChange;
  FWriteBom := Value;
end;

procedure TLandrixXmlWriter.SetStandalone(Value: TLandrixXmlStandalone);
begin
  CheckOptionChange;
  FStandalone := Value;
end;

procedure TLandrixXmlWriter.SetIndent(Value: Boolean);
begin
  CheckOptionChange;
  FIndent := Value;
end;

procedure TLandrixXmlWriter.SetIndentString(const Value: TLandrixXmlUtf8);
var
  I: Integer;
begin
  CheckOptionChange;
  for I := 1 to Length(Value) do
    if (Value[I] <> ' ') and (Value[I] <> #9) then
      raise ELandrixXmlError.CreateCode(xecInvalidArgument,
        'IndentString may only contain spaces and TABs');
  FIndentString := Value;
end;

procedure TLandrixXmlWriter.SetLineBreak(Value: TLandrixXmlLineBreak);
begin
  CheckOptionChange;
  FLineBreak := Value;
end;

function TLandrixXmlWriter.GetBytesWritten: Int64;
begin
  Result := FFlushed + FBuf.Size;
end;

{ --- errors and atomicity ----------------------------------------------- }

function TLandrixXmlWriter.ElementPath: string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to FElemCount - 1 do
    Result := Result + '/' + LandrixXmlEscapeForMessage(FElems[I].QName, 60);
  if Result = '' then
    Result := '/';
end;

procedure TLandrixXmlWriter.Fail(Code: TLandrixXmlErrorCode; const Msg: string);
begin
  raise ELandrixXmlError.CreateCode(Code, Msg + ' at ' + ElementPath);
end;

procedure TLandrixXmlWriter.FailAt(Code: TLandrixXmlErrorCode; const Msg: string;
  Offset: Integer);
begin
  raise ELandrixXmlError.CreateAt(Code, Msg + ' at ' + ElementPath, 0, 0, Offset);
end;

procedure TLandrixXmlWriter.CheckUsable;
begin
  if FBroken then
    raise ELandrixXmlError.CreateCode(xecInvalidOperation,
      'The writer is unusable after an output error; call Clear');
  if FFinished then
    raise ELandrixXmlError.CreateCode(xecInvalidOperation,
      'The document is already finished; call Clear to write another one');
end;

procedure TLandrixXmlWriter.TakeSnapshot(out S: TLandrixXmlWriterSnapshot);
begin
  S.BufSize := FBuf.Size;
  S.Flushed := FFlushed;
  S.ElemCount := FElemCount;
  S.AttrCount := FAttrCount;
  S.BindingCount := FBindingCount;
  S.TopCount := FTopCount;
  S.InStartTag := FInStartTag;
  S.Started := FStarted;
  S.RootDone := FRootDone;
  S.HasDocType := FHasDocType;
  if FElemCount > 0 then
    S.Top := FElems[FElemCount - 1];
end;

procedure TLandrixXmlWriter.Rollback(const S: TLandrixXmlWriterSnapshot);
begin
  if FFlushed <> S.Flushed then
  begin
    { part of the output already left the writer }
    FBroken := True;
    Exit;
  end;
  FBuf.Truncate(S.BufSize);
  FElemCount := S.ElemCount;
  FAttrCount := S.AttrCount;
  FBindingCount := S.BindingCount;
  FTopCount := S.TopCount;
  FInStartTag := S.InStartTag;
  FStarted := S.Started;
  FRootDone := S.RootDone;
  FHasDocType := S.HasDocType;
  if FElemCount > 0 then
    FElems[FElemCount - 1] := S.Top;
  FHashCount := -1;
end;

procedure TLandrixXmlWriter.FlushBuffer;
var
  N: Integer;
begin
  if (FStream = nil) or (FBuf.Size = 0) then
    Exit;
  N := FBuf.Size;
  try
    FBuf.WriteToStream(FStream);
  except
    FBroken := True;
    raise;
  end;
  Inc(FFlushed, N);
  FBuf.Clear;
end;

procedure TLandrixXmlWriter.AfterCall;
begin
  if (FStream <> nil) and (FBuf.Size >= FlushThreshold) then
    FlushBuffer;
end;

procedure TLandrixXmlWriter.Flush;
begin
  if FBroken then
    CheckUsable;
  FlushBuffer;
end;

{ --- low-level output ------------------------------------------------------ }

procedure TLandrixXmlWriter.AppendLit(const S: AnsiString);
begin
  if S <> '' then
    FBuf.Append(PAnsiChar(S)^, Length(S));
end;

procedure TLandrixXmlWriter.AppendStr(const S: TLandrixXmlUtf8);
begin
  if S <> '' then
    FBuf.Append(PAnsiChar(S)^, Length(S));
end;

procedure TLandrixXmlWriter.AppendLineBreak;
begin
  if FLineBreak = xlbCRLF then
    AppendLit(#13#10)
  else
    AppendLit(#10);
end;

procedure TLandrixXmlWriter.WriteIndent(Level: Integer);
var
  I: Integer;
begin
  AppendLineBreak;
  for I := 1 to Level do
    AppendStr(FIndentString);
end;

procedure TLandrixXmlWriter.EnsureStarted;
begin
  if FStarted then
    Exit;
  FStarted := True;
  if FWriteBom then
  begin
    FBuf.AppendByte($EF);
    FBuf.AppendByte($BB);
    FBuf.AppendByte($BF);
  end;
  if FWriteDeclaration then
  begin
    AppendLit('<?xml version="1.0" encoding="UTF-8"');
    case FStandalone of
      xsaYes: AppendLit(' standalone="yes"');
      xsaNo: AppendLit(' standalone="no"');
    else
      ;
    end;
    AppendLit('?>');
    AppendLineBreak;
  end;
end;

procedure TLandrixXmlWriter.BeforeTopLevel;
begin
  EnsureStarted;
  if FIndent and (FTopCount > 0) then
    AppendLineBreak;
  Inc(FTopCount);
end;

{ Before a child element, comment or PI inside the current element. }
procedure TLandrixXmlWriter.BeforeChild;
var
  I: Integer;
begin
  if FInStartTag then
    CloseStartTag(False);
  I := FElemCount - 1;
  if FIndent and not FElems[I].Mixed and not FElems[I].HasText then
    WriteIndent(FElemCount);
  FElems[I].HasChildren := True;
end;

{ Before character data inside the current element. }
procedure TLandrixXmlWriter.BeforeText;
var
  I: Integer;
begin
  if FInStartTag then
    CloseStartTag(False);
  I := FElemCount - 1;
  if FIndent and not FElems[I].Mixed and FElems[I].HasChildren and
    not FElems[I].HasText then
    Fail(xecWrite, 'Text after indented child nodes would change the content; ' +
      'start the element with Mixed = True');
  FElems[I].HasText := True;
end;

{ Validates Len bytes of UTF-8 at P and appends them, escaped for Mode. }
procedure TLandrixXmlWriter.Emit(P: PAnsiChar; Len: Integer; Mode: Integer;
  const What: string);
var
  I, Run, N: Integer;
  C: AnsiChar;
  CodePoint: Cardinal;
  Ref: AnsiString;
begin
  I := 0;
  Run := 0;
  while I < Len do
  begin
    C := P[I];
    if Ord(C) < $80 then
    begin
      Ref := '';
      case C of
        '&':
          if Mode <> emRaw then
            Ref := '&amp;';
        '<':
          if Mode <> emRaw then
            Ref := '&lt;';
        '>':
          if Mode <> emRaw then
            Ref := '&gt;';
        '"':
          if Mode = emAttribute then
            Ref := '&quot;';
        #9:
          if Mode = emAttribute then
            Ref := '&#9;';
        #10:
          if Mode = emAttribute then
            Ref := '&#10;';
        #13:
          if Mode = emRaw then
            FailAt(xecWrite, 'A carriage return cannot be preserved in ' + What, I)
          else
            Ref := '&#13;';
      else
        if Ord(C) < $20 then
          FailAt(xecInvalidChar, 'Character U+' + IntToHex(Ord(C), 4) +
            ' is not allowed in XML 1.0 (' + What + ')', I);
      end;
      if Ref <> '' then
      begin
        if I > Run then
          FBuf.Append(P[Run], I - Run);
        AppendLit(Ref);
        Run := I + 1;
      end;
      Inc(I);
    end
    else
    begin
      N := LandrixXmlDecodeUtf8(P + I, Len - I, CodePoint);
      if N = 0 then
        FailAt(xecInvalidUnicode, 'Invalid UTF-8 byte sequence in ' + What, I);
      if not LandrixXmlIsXmlChar(CodePoint) then
        FailAt(xecInvalidChar, 'Character U+' + IntToHex(Integer(CodePoint), 4) +
          ' is not allowed in XML 1.0 (' + What + ')', I);
      Inc(I, N);
    end;
  end;
  if Len > Run then
    FBuf.Append(P[Run], Len - Run);
end;

{ Validates a value without writing it. }
procedure TLandrixXmlWriter.CheckValue(P: PAnsiChar; Len: Integer; const What: string);
var
  Size: Integer;
begin
  Size := FBuf.Size;
  try
    Emit(P, Len, emRaw, What);
  finally
    FBuf.Truncate(Size);
  end;
end;

{ --- names and namespaces ------------------------------------------------ }

{ Checks an XML name with namespace rules; returns the colon position
  (0-based) or -1. }
function TLandrixXmlWriter.CheckQName(const QName: TLandrixXmlUtf8;
  const What: string): Integer;
var
  I, Bad, N: Integer;
  CodePoint: Cardinal;
begin
  Bad := LandrixXmlCheckName(PAnsiChar(QName), Length(QName));
  if Bad >= 0 then
  begin
    if QName = '' then
      Fail(xecWrite, 'Empty ' + What)
    else
      Fail(xecWrite, 'Invalid ' + What + ' "' + LandrixXmlEscapeForMessage(QName, 60) +
        '" (offset ' + IntToStr(Bad) + ')');
  end;
  Result := -1;
  for I := 0 to Length(QName) - 1 do
    if PAnsiChar(QName)[I] = ':' then
    begin
      if Result >= 0 then
        Fail(xecNamespace, 'Qualified name with more than one colon: "' +
          LandrixXmlEscapeForMessage(QName, 60) + '"');
      Result := I;
    end;
  if Result < 0 then
    Exit;
  if (Result = 0) or (Result = Length(QName) - 1) then
    Fail(xecNamespace, 'Qualified name with empty prefix or local part: "' +
      LandrixXmlEscapeForMessage(QName, 60) + '"');
  N := LandrixXmlDecodeUtf8(PAnsiChar(QName) + Result + 1, Length(QName) - Result - 1,
    CodePoint);
  if (N = 0) or not LandrixXmlIsNameStartChar(CodePoint) then
    Fail(xecNamespace, 'Invalid local name in qualified name "' +
      LandrixXmlEscapeForMessage(QName, 60) + '"');
end;

procedure TLandrixXmlWriter.CheckNcName(const Name: TLandrixXmlUtf8; const What: string);
begin
  if CheckQName(Name, What) >= 0 then
    Fail(xecNamespace, 'The ' + What + ' must not contain a colon: "' +
      LandrixXmlEscapeForMessage(Name, 60) + '"');
end;

procedure TLandrixXmlWriter.CheckNsArgs(const NamespaceUri, Prefix,
  LocalName: TLandrixXmlUtf8; IsAttribute: Boolean);
begin
  CheckNcName(LocalName, 'local name');
  if Prefix <> '' then
    CheckNcName(Prefix, 'prefix');
  CheckValue(PAnsiChar(NamespaceUri), Length(NamespaceUri), 'namespace name');
  if SameAscii(Prefix, 'xmlns') or (NamespaceUri = LandrixXmlNamespaceXmlns) then
    Fail(xecNamespace, 'Use DeclareNamespace for namespace declarations');
  if SameAscii(Prefix, 'xml') <> (NamespaceUri = LandrixXmlNamespaceXml) then
    Fail(xecNamespace, 'The prefix "xml" and the XML namespace belong together');
  if (Prefix <> '') and (NamespaceUri = '') then
    Fail(xecInvalidArgument, 'A prefix needs a non-empty namespace name');
  if IsAttribute and (Prefix = '') and (NamespaceUri <> '') then
    Fail(xecInvalidArgument, 'A namespaced attribute needs a prefix');
end;

function TLandrixXmlWriter.FindBinding(const Prefix: TLandrixXmlUtf8): Integer;
begin
  Result := FBindingCount - 1;
  while (Result >= 0) and (FBindings[Result].Prefix <> Prefix) do
    Dec(Result);
end;

procedure TLandrixXmlWriter.RebuildHash;
var
  Size, I, Slot: Integer;
begin
  Size := 32;
  while Size < 4 * (FAttrCount + 1) do
    Size := Size * 2;
  if Length(FHash) < Size then
    SetLength(FHash, Size)
  else
    Size := Integer(Length(FHash));
  for I := 0 to Size - 1 do
    FHash[I] := -1;
  for I := 0 to FAttrCount - 1 do
  begin
    Slot := Integer(LandrixXmlHashBytes(PAnsiChar(FAttrs[I].QName), Length(FAttrs[I].QName),
      LandrixXmlHashSeed) and Cardinal(Size - 1));
    while FHash[Slot] >= 0 do
      Slot := (Slot + 1) and (Size - 1);
    FHash[Slot] := I;
  end;
  FHashCount := FAttrCount;
end;

{ Index of the pending attribute with this qualified name, or -1. }
function TLandrixXmlWriter.FindAttr(const QName: TLandrixXmlUtf8): Integer;
var
  Slot, Size: Integer;
begin
  if FAttrCount < HashThreshold then
  begin
    Result := FAttrCount - 1;
    while (Result >= 0) and (FAttrs[Result].QName <> QName) do
      Dec(Result);
    Exit;
  end;
  if (FHashCount <> FAttrCount) or (Length(FHash) < 2 * (FAttrCount + 1)) then
    RebuildHash;
  Size := Integer(Length(FHash));
  Slot := Integer(LandrixXmlHashBytes(PAnsiChar(QName), Length(QName), LandrixXmlHashSeed) and
    Cardinal(Size - 1));
  while FHash[Slot] >= 0 do
  begin
    if FAttrs[FHash[Slot]].QName = QName then
    begin
      Result := FHash[Slot];
      Exit;
    end;
    Slot := (Slot + 1) and (Size - 1);
  end;
  Result := -1;
end;

{ True if the current start tag already uses Prefix in a name whose
  namespace comes from the bindings in scope (not guaranteed by a ...Ns
  method). }
function TLandrixXmlWriter.UsesPrefixLexically(const Prefix: TLandrixXmlUtf8): Boolean;
var
  E, I: Integer;
begin
  Result := True;
  E := FElemCount - 1;
  if not FElems[E].HasRequiredUri and
    (SubUtf8(FElems[E].QName, 0, FElems[E].ColonPos) = Prefix) then
    Exit;
  if Prefix <> '' then
    for I := 0 to FAttrCount - 1 do
      if not FAttrs[I].IsNsDecl and not FAttrs[I].HasRequiredUri and
        (FAttrs[I].ColonPos >= 0) and
        (SubUtf8(FAttrs[I].QName, 0, FAttrs[I].ColonPos) = Prefix) then
        Exit;
  Result := False;
end;

{ Enters the attribute just appended into the hash table when the table is
  current and large enough; otherwise marks it stale (rebuilt on demand). }
procedure TLandrixXmlWriter.HashAdded;
var
  Size, Slot: Integer;
begin
  if (FHashCount <> FAttrCount - 1) or (Length(FHash) < 2 * (FAttrCount + 1)) then
  begin
    FHashCount := -1;
    Exit;
  end;
  Size := Integer(Length(FHash));
  Slot := Integer(LandrixXmlHashBytes(PAnsiChar(FAttrs[FAttrCount - 1].QName),
    Length(FAttrs[FAttrCount - 1].QName), LandrixXmlHashSeed) and Cardinal(Size - 1));
  while FHash[Slot] >= 0 do
    Slot := (Slot + 1) and (Size - 1);
  FHash[Slot] := FAttrCount - 1;
  FHashCount := FAttrCount;
end;

{ Ensures Prefix is bound to Uri on the current start tag, declaring it
  there (immediately) when necessary. }
procedure TLandrixXmlWriter.Require(const Prefix, Uri: TLandrixXmlUtf8);
var
  B: Integer;
begin
  B := FindBinding(Prefix);
  if B >= 0 then
  begin
    if FBindings[B].Uri = Uri then
      Exit;
    if B >= FElems[FElemCount - 1].BindingTop then
      Fail(xecNamespace, 'The prefix "' + LandrixXmlEscapeForMessage(Prefix, 60) +
        '" is already bound to another namespace on this element');
    if UsesPrefixLexically(Prefix) then
      Fail(xecNamespace, 'Declaring the prefix "' + LandrixXmlEscapeForMessage(Prefix, 60) +
        '" here would change the namespace of a name already written on this element');
  end
  else if (Prefix = '') and (Uri = '') then
    Exit;
  DeclareCore(Prefix, Uri);
end;

procedure TLandrixXmlWriter.CheckExpandedDuplicates;
var
  I, J, Size, Slot, Count: Integer;
  H: Cardinal;

  function Relevant(A: Integer): Boolean;
  begin
    Result := (FAttrs[A].ColonPos >= 0) and not FAttrs[A].IsNsDecl;
  end;

  function Same(A, B: Integer): Boolean;
  begin
    Result := (FAttrs[A].Uri = FAttrs[B].Uri) and SameBytes(
      PAnsiChar(FAttrs[A].QName) + FAttrs[A].ColonPos + 1,
      Length(FAttrs[A].QName) - FAttrs[A].ColonPos - 1,
      PAnsiChar(FAttrs[B].QName) + FAttrs[B].ColonPos + 1,
      Length(FAttrs[B].QName) - FAttrs[B].ColonPos - 1);
  end;

  procedure Duplicate(A: Integer);
  begin
    Fail(xecNamespace, 'Duplicate attribute "' + LandrixXmlEscapeForMessage(
      FAttrs[A].QName, 60) + '" (same namespace and local name)');
  end;

begin
  Count := 0;
  for I := 0 to FAttrCount - 1 do
    if Relevant(I) then
      Inc(Count);
  if Count < 2 then
    Exit;
  if Count < HashThreshold then
  begin
    for I := 1 to FAttrCount - 1 do
      if Relevant(I) then
        for J := 0 to I - 1 do
          if Relevant(J) and Same(I, J) then
            Duplicate(I);
    Exit;
  end;
  Size := 32;
  while Size < 4 * Count do
    Size := Size * 2;
  if Length(FHash) < Size then
    SetLength(FHash, Size)
  else
    Size := Integer(Length(FHash));
  FHashCount := -1;
  for I := 0 to Size - 1 do
    FHash[I] := -1;
  for I := 0 to FAttrCount - 1 do
  begin
    if not Relevant(I) then
      Continue;
    H := LandrixXmlHashBytes(PAnsiChar(FAttrs[I].QName) + FAttrs[I].ColonPos + 1,
      Length(FAttrs[I].QName) - FAttrs[I].ColonPos - 1,
      LandrixXmlHashBytes(PAnsiChar(FAttrs[I].Uri), Length(FAttrs[I].Uri),
      LandrixXmlHashSeed));
    Slot := Integer(H and Cardinal(Size - 1));
    while FHash[Slot] >= 0 do
    begin
      if Same(I, FHash[Slot]) then
        Duplicate(I);
      Slot := (Slot + 1) and (Size - 1);
    end;
    FHash[Slot] := I;
  end;
end;

procedure TLandrixXmlWriter.CloseStartTag(Empty: Boolean);
var
  I, E, B: Integer;
begin
  E := FElemCount - 1;
  { every prefix must be declared by now }
  if FElems[E].ColonPos >= 0 then
  begin
    if FindBinding(SubUtf8(FElems[E].QName, 0, FElems[E].ColonPos)) < 0 then
      Fail(xecNamespace, 'Undeclared namespace prefix "' + LandrixXmlEscapeForMessage(
        SubUtf8(FElems[E].QName, 0, FElems[E].ColonPos), 60) + '"');
  end;
  for I := 0 to FAttrCount - 1 do
  begin
    if FAttrs[I].IsNsDecl or (FAttrs[I].ColonPos < 0) then
      Continue;
    B := FindBinding(SubUtf8(FAttrs[I].QName, 0, FAttrs[I].ColonPos));
    if B < 0 then
      Fail(xecNamespace, 'Undeclared namespace prefix "' + LandrixXmlEscapeForMessage(
        SubUtf8(FAttrs[I].QName, 0, FAttrs[I].ColonPos), 60) + '"');
    FAttrs[I].Uri := FBindings[B].Uri;
  end;
  CheckExpandedDuplicates;
  if Empty then
    AppendLit('/>')
  else
    AppendLit('>');
  FInStartTag := False;
  FAttrCount := 0;
  FHashCount := -1;
end;

{ --- core operations (run inside a snapshot) ------------------------------ }

procedure TLandrixXmlWriter.StartElementCore(const QName: TLandrixXmlUtf8;
  ColonPos: Integer; const RequiredUri: TLandrixXmlUtf8; HasRequiredUri, Mixed: Boolean);
var
  ParentMixed, ParentPreserve: Boolean;
  P: Integer;
begin
  if (ColonPos = 5) and SameAscii(SubUtf8(QName, 0, 5), 'xmlns') then
    Fail(xecNamespace, 'Element names must not have the prefix "xmlns"');
  if FElemCount = 0 then
  begin
    if FRootDone then
      Fail(xecInvalidOperation, 'Only one root element is allowed');
    BeforeTopLevel;
    ParentMixed := False;
    ParentPreserve := False;
  end
  else
  begin
    BeforeChild;
    P := FElemCount - 1;
    ParentMixed := FElems[P].OwnMixed or FElems[P].InheritedMixed;
    ParentPreserve := (FElems[P].Space = 1) or
      ((FElems[P].Space = 0) and FElems[P].InheritedPreserve);
  end;
  if FElemCount = Length(FElems) then
  begin
    if FElemCount = 0 then
      SetLength(FElems, 32)
    else
      SetLength(FElems, 2 * FElemCount);
  end;
  FElems[FElemCount].QName := QName;
  FElems[FElemCount].ColonPos := ColonPos;
  FElems[FElemCount].RequiredUri := RequiredUri;
  FElems[FElemCount].HasRequiredUri := HasRequiredUri;
  FElems[FElemCount].BindingTop := FBindingCount;
  FElems[FElemCount].OwnMixed := Mixed;
  FElems[FElemCount].InheritedMixed := ParentMixed;
  FElems[FElemCount].InheritedPreserve := ParentPreserve;
  FElems[FElemCount].Space := 0;
  FElems[FElemCount].Mixed := Mixed or ParentMixed or ParentPreserve;
  FElems[FElemCount].HasText := False;
  FElems[FElemCount].HasChildren := False;
  Inc(FElemCount);
  AppendLit('<');
  AppendStr(QName);
  FInStartTag := True;
  FAttrCount := 0;
  FHashCount := -1;
  if HasRequiredUri then
    Require(SubUtf8(QName, 0, ColonPos), RequiredUri);
end;

procedure TLandrixXmlWriter.EndElementCore;
var
  I: Integer;
begin
  if FElemCount = 0 then
    Fail(xecInvalidOperation, 'No open element to end');
  I := FElemCount - 1;
  if FInStartTag then
    CloseStartTag(True)
  else
  begin
    if FIndent and not FElems[I].Mixed and not FElems[I].HasText and
      FElems[I].HasChildren then
      WriteIndent(I);
    AppendLit('</');
    AppendStr(FElems[I].QName);
    AppendLit('>');
  end;
  FBindingCount := FElems[I].BindingTop;
  FElemCount := I;
  if I = 0 then
    FRootDone := True;
end;

procedure TLandrixXmlWriter.DeclareCore(const Prefix, Uri: TLandrixXmlUtf8);
var
  Name: TLandrixXmlUtf8;
  E, I: Integer;
begin
  if not FInStartTag then
    Fail(xecInvalidOperation, 'Namespace declarations must directly follow StartElement');
  if Prefix <> '' then
    CheckNcName(Prefix, 'prefix');
  CheckValue(PAnsiChar(Uri), Length(Uri), 'namespace name');
  if SameAscii(Prefix, 'xmlns') then
    Fail(xecNamespace, 'The prefix "xmlns" must not be declared');
  if SameAscii(Prefix, 'xml') then
  begin
    if Uri <> LandrixXmlNamespaceXml then
      Fail(xecNamespace, 'The prefix "xml" must not be bound to another namespace');
  end
  else
  begin
    if (Uri = LandrixXmlNamespaceXml) or (Uri = LandrixXmlNamespaceXmlns) then
      Fail(xecNamespace, 'Reserved namespace name must not be declared');
    if (Prefix <> '') and (Uri = '') then
      Fail(xecNamespace, 'A prefix must not be bound to an empty namespace name');
  end;
  { must not contradict a namespace guaranteed by StartElementNs/AttributeNs }
  E := FElemCount - 1;
  if FElems[E].HasRequiredUri and (FElems[E].RequiredUri <> Uri) and
    (SubUtf8(FElems[E].QName, 0, FElems[E].ColonPos) = Prefix) then
    Fail(xecNamespace, 'The declaration contradicts the namespace of the element');
  for I := 0 to FAttrCount - 1 do
    if FAttrs[I].HasRequiredUri and (FAttrs[I].RequiredUri <> Uri) and
      (SubUtf8(FAttrs[I].QName, 0, FAttrs[I].ColonPos) = Prefix) then
      Fail(xecNamespace, 'The declaration contradicts the namespace of an attribute');
  if Prefix = '' then
    Name := 'xmlns'
  else
    Name := JoinQName('xmlns', Prefix);
  if FindAttr(Name) >= 0 then
    Fail(xecWrite, 'Duplicate namespace declaration "' +
      LandrixXmlEscapeForMessage(Name, 60) + '"');
  if FAttrCount = Length(FAttrs) then
  begin
    if FAttrCount = 0 then
      SetLength(FAttrs, 16)
    else
      SetLength(FAttrs, 2 * FAttrCount);
  end;
  FAttrs[FAttrCount].QName := Name;
  if Prefix = '' then
    FAttrs[FAttrCount].ColonPos := -1
  else
    FAttrs[FAttrCount].ColonPos := 5;
  FAttrs[FAttrCount].RequiredUri := '';
  FAttrs[FAttrCount].HasRequiredUri := False;
  FAttrs[FAttrCount].IsNsDecl := True;
  FAttrs[FAttrCount].Uri := LandrixXmlNamespaceXmlns;
  Inc(FAttrCount);
  HashAdded;
  AppendLit(' ');
  AppendStr(Name);
  AppendLit('="');
  Emit(PAnsiChar(Uri), Length(Uri), emAttribute, 'namespace name');
  AppendLit('"');
  if FBindingCount = Length(FBindings) then
    SetLength(FBindings, 2 * FBindingCount);
  FBindings[FBindingCount].Prefix := Prefix;
  FBindings[FBindingCount].Uri := Uri;
  Inc(FBindingCount);
end;

procedure TLandrixXmlWriter.AttributeCore(const QName: TLandrixXmlUtf8; ColonPos: Integer;
  const RequiredUri: TLandrixXmlUtf8; HasRequiredUri: Boolean; const Value: TLandrixXmlUtf8);
var
  E: Integer;
begin
  if not FInStartTag then
    Fail(xecInvalidOperation, 'Attributes must directly follow StartElement');
  if SameAscii(QName, 'xmlns') then
  begin
    DeclareCore('', Value);
    Exit;
  end;
  if (ColonPos = 5) and SameAscii(SubUtf8(QName, 0, 5), 'xmlns') then
  begin
    DeclareCore(SubUtf8(QName, 6, Length(QName) - 6), Value);
    Exit;
  end;
  if FindAttr(QName) >= 0 then
    Fail(xecWrite, 'Duplicate attribute "' + LandrixXmlEscapeForMessage(QName, 60) + '"');
  if HasRequiredUri then
    Require(SubUtf8(QName, 0, ColonPos), RequiredUri);
  if FAttrCount = Length(FAttrs) then
  begin
    if FAttrCount = 0 then
      SetLength(FAttrs, 16)
    else
      SetLength(FAttrs, 2 * FAttrCount);
  end;
  AppendLit(' ');
  AppendStr(QName);
  AppendLit('="');
  Emit(PAnsiChar(Value), Length(Value), emAttribute, 'attribute value');
  AppendLit('"');
  FAttrs[FAttrCount].QName := QName;
  FAttrs[FAttrCount].ColonPos := ColonPos;
  FAttrs[FAttrCount].RequiredUri := RequiredUri;
  FAttrs[FAttrCount].HasRequiredUri := HasRequiredUri;
  FAttrs[FAttrCount].IsNsDecl := False;
  FAttrs[FAttrCount].Uri := '';
  Inc(FAttrCount);
  HashAdded;
  if SameAscii(QName, 'xml:space') then
  begin
    E := FElemCount - 1;
    if SameAscii(Value, 'preserve') then
      FElems[E].Space := 1
    else if SameAscii(Value, 'default') then
      FElems[E].Space := 2;
    { xml:space="default" only cancels an inherited "preserve", never a
      Mixed = True given by the caller }
    FElems[E].Mixed := FElems[E].OwnMixed or FElems[E].InheritedMixed or
      (FElems[E].Space = 1) or ((FElems[E].Space = 0) and FElems[E].InheritedPreserve);
  end;
end;

{ --- public operations ------------------------------------------------------ }

procedure TLandrixXmlWriter.StartDocument;
var
  S: TLandrixXmlWriterSnapshot;
begin
  CheckUsable;
  if FStarted then
    Fail(xecInvalidOperation, 'StartDocument must be the first call');
  TakeSnapshot(S);
  try
    EnsureStarted;
  except
    Rollback(S);
    raise;
  end;
  AfterCall;
end;

procedure TLandrixXmlWriter.EndDocument;
begin
  CheckUsable;
  if FElemCount > 0 then
    Fail(xecInvalidOperation, 'EndDocument with open elements');
  if not FRootDone then
    Fail(xecInvalidOperation, 'EndDocument without a root element');
  FFinished := True;
  FlushBuffer;
end;

procedure TLandrixXmlWriter.DoStartElement(const QName: TLandrixXmlUtf8; Mixed: Boolean);
var
  S: TLandrixXmlWriterSnapshot;
begin
  CheckUsable;
  TakeSnapshot(S);
  try
    StartElementCore(QName, CheckQName(QName, 'element name'), '', False, Mixed);
  except
    Rollback(S);
    raise;
  end;
  AfterCall;
end;

procedure TLandrixXmlWriter.DoStartElementNs(const NamespaceUri, Prefix,
  LocalName: TLandrixXmlUtf8; Mixed: Boolean);
var
  S: TLandrixXmlWriterSnapshot;
begin
  CheckUsable;
  TakeSnapshot(S);
  try
    CheckNsArgs(NamespaceUri, Prefix, LocalName, False);
    if Prefix = '' then
      StartElementCore(LocalName, -1, NamespaceUri, True, Mixed)
    else
      StartElementCore(JoinQName(Prefix, LocalName), Length(Prefix), NamespaceUri, True, Mixed);
  except
    Rollback(S);
    raise;
  end;
  AfterCall;
end;

procedure TLandrixXmlWriter.StartElement(const QName: TLandrixXmlUtf8; Mixed: Boolean);
begin
  DoStartElement(QName, Mixed);
end;

procedure TLandrixXmlWriter.StartElementNs(const NamespaceUri, Prefix,
  LocalName: TLandrixXmlUtf8; Mixed: Boolean);
begin
  DoStartElementNs(NamespaceUri, Prefix, LocalName, Mixed);
end;

procedure TLandrixXmlWriter.EndElement;
var
  S: TLandrixXmlWriterSnapshot;
begin
  CheckUsable;
  TakeSnapshot(S);
  try
    EndElementCore;
  except
    Rollback(S);
    raise;
  end;
  AfterCall;
end;

procedure TLandrixXmlWriter.DeclareNamespace(const Prefix, NamespaceUri: TLandrixXmlUtf8);
var
  S: TLandrixXmlWriterSnapshot;
begin
  CheckUsable;
  TakeSnapshot(S);
  try
    DeclareCore(Prefix, NamespaceUri);
  except
    Rollback(S);
    raise;
  end;
  AfterCall;
end;

procedure TLandrixXmlWriter.DoAttribute(const QName, Value: TLandrixXmlUtf8);
var
  S: TLandrixXmlWriterSnapshot;
begin
  CheckUsable;
  TakeSnapshot(S);
  try
    AttributeCore(QName, CheckQName(QName, 'attribute name'), '', False, Value);
  except
    Rollback(S);
    raise;
  end;
  AfterCall;
end;

procedure TLandrixXmlWriter.DoAttributeNs(const NamespaceUri, Prefix, LocalName,
  Value: TLandrixXmlUtf8);
var
  S: TLandrixXmlWriterSnapshot;
begin
  CheckUsable;
  TakeSnapshot(S);
  try
    CheckNsArgs(NamespaceUri, Prefix, LocalName, True);
    if Prefix = '' then
      AttributeCore(LocalName, -1, '', False, Value)
    else
      AttributeCore(JoinQName(Prefix, LocalName), Length(Prefix), NamespaceUri, True, Value);
  except
    Rollback(S);
    raise;
  end;
  AfterCall;
end;

procedure TLandrixXmlWriter.DoElement(const QName, Value: TLandrixXmlUtf8);
var
  S: TLandrixXmlWriterSnapshot;
begin
  CheckUsable;
  TakeSnapshot(S);
  try
    StartElementCore(QName, CheckQName(QName, 'element name'), '', False, False);
    if Value <> '' then
    begin
      BeforeText;
      Emit(PAnsiChar(Value), Length(Value), emText, 'text');
    end;
    EndElementCore;
  except
    Rollback(S);
    raise;
  end;
  AfterCall;
end;

procedure TLandrixXmlWriter.DoElementNs(const NamespaceUri, Prefix, LocalName,
  Value: TLandrixXmlUtf8);
var
  S: TLandrixXmlWriterSnapshot;
begin
  CheckUsable;
  TakeSnapshot(S);
  try
    CheckNsArgs(NamespaceUri, Prefix, LocalName, False);
    if Prefix = '' then
      StartElementCore(LocalName, -1, NamespaceUri, True, False)
    else
      StartElementCore(JoinQName(Prefix, LocalName), Length(Prefix), NamespaceUri, True, False);
    if Value <> '' then
    begin
      BeforeText;
      Emit(PAnsiChar(Value), Length(Value), emText, 'text');
    end;
    EndElementCore;
  except
    Rollback(S);
    raise;
  end;
  AfterCall;
end;

procedure TLandrixXmlWriter.DoText(const Value: TLandrixXmlUtf8);
var
  S: TLandrixXmlWriterSnapshot;
  I: Integer;
begin
  CheckUsable;
  if Value = '' then
    Exit;
  TakeSnapshot(S);
  try
    if FElemCount = 0 then
    begin
      { outside the root element only white space, written literally }
      for I := 1 to Length(Value) do
        if not IsSpace(Value[I]) then
          FailAt(xecWrite, 'Only white space is allowed outside the root element', I - 1);
      EnsureStarted;
      AppendStr(Value);
    end
    else
    begin
      BeforeText;
      Emit(PAnsiChar(Value), Length(Value), emText, 'text');
    end;
  except
    Rollback(S);
    raise;
  end;
  AfterCall;
end;

procedure TLandrixXmlWriter.DoCData(const Value: TLandrixXmlUtf8);
var
  S: TLandrixXmlWriterSnapshot;
  Pos: Integer;
begin
  CheckUsable;
  TakeSnapshot(S);
  try
    if FElemCount = 0 then
      Fail(xecInvalidOperation, 'CDATA sections are only allowed inside an element');
    Pos := FindSeq(PAnsiChar(Value), Length(Value), ']]>');
    if Pos >= 0 then
      FailAt(xecWrite, 'A CDATA section must not contain "]]>"', Pos);
    BeforeText;
    AppendLit('<![CDATA[');
    Emit(PAnsiChar(Value), Length(Value), emRaw, 'CDATA section');
    AppendLit(']]>');
  except
    Rollback(S);
    raise;
  end;
  AfterCall;
end;

procedure TLandrixXmlWriter.DoComment(const Value: TLandrixXmlUtf8);
var
  S: TLandrixXmlWriterSnapshot;
  Pos: Integer;
begin
  CheckUsable;
  TakeSnapshot(S);
  try
    Pos := FindSeq(PAnsiChar(Value), Length(Value), '--');
    if Pos >= 0 then
      FailAt(xecWrite, 'A comment must not contain "--"', Pos);
    if (Value <> '') and (Value[Length(Value)] = '-') then
      FailAt(xecWrite, 'A comment must not end with "-"', Length(Value) - 1);
    if FElemCount = 0 then
      BeforeTopLevel
    else
      BeforeChild;
    AppendLit('<!--');
    Emit(PAnsiChar(Value), Length(Value), emRaw, 'comment');
    AppendLit('-->');
  except
    Rollback(S);
    raise;
  end;
  AfterCall;
end;

procedure TLandrixXmlWriter.DoProcessingInstruction(const Target, Data: TLandrixXmlUtf8);
var
  S: TLandrixXmlWriterSnapshot;
  Pos: Integer;
begin
  CheckUsable;
  TakeSnapshot(S);
  try
    CheckNcName(Target, 'processing instruction target');
    if (Length(Target) = 3) and ((Target[1] = 'x') or (Target[1] = 'X')) and
      ((Target[2] = 'm') or (Target[2] = 'M')) and ((Target[3] = 'l') or (Target[3] = 'L')) then
      Fail(xecWrite, 'Processing instruction targets "xml" are reserved');
    Pos := FindSeq(PAnsiChar(Data), Length(Data), '?>');
    if Pos >= 0 then
      FailAt(xecWrite, 'Processing instruction data must not contain "?>"', Pos);
    if (Data <> '') and IsSpace(Data[1]) then
      FailAt(xecWrite, 'Processing instruction data must not start with white space', 0);
    if FElemCount = 0 then
      BeforeTopLevel
    else
      BeforeChild;
    AppendLit('<?');
    AppendStr(Target);
    if Data <> '' then
    begin
      AppendLit(' ');
      Emit(PAnsiChar(Data), Length(Data), emRaw, 'processing instruction');
    end;
    AppendLit('?>');
  except
    Rollback(S);
    raise;
  end;
  AfterCall;
end;

procedure TLandrixXmlWriter.DocumentType(const Name, Content: TLandrixXmlUtf8);
var
  S: TLandrixXmlWriterSnapshot;
  P: PAnsiChar;
  I, Len, Pos: Integer;
  InSubset: Boolean;
  Quote: AnsiChar;
begin
  CheckUsable;
  TakeSnapshot(S);
  try
    if (FElemCount > 0) or FRootDone or FHasDocType then
      Fail(xecInvalidOperation,
        'The document type declaration must come once, before the root element');
    if LandrixXmlCheckName(PAnsiChar(Name), Length(Name)) >= 0 then
      Fail(xecWrite, 'Invalid document type name "' + LandrixXmlEscapeForMessage(Name, 60) + '"');
    P := PAnsiChar(Content);
    Len := Length(Content);
    if (Len > 0) and not IsSpace(P[0]) then
      FailAt(xecWrite, 'Document type content must start with white space', 0);
    InSubset := False;
    I := 0;
    while I < Len do
    begin
      case P[I] of
        '"', '''':
          begin
            Quote := P[I];
            Inc(I);
            while (I < Len) and (P[I] <> Quote) do
              Inc(I);
            if I >= Len then
              FailAt(xecWrite, 'Unterminated literal in document type content', Len);
          end;
        '[':
          if InSubset then
            FailAt(xecWrite, 'Unexpected "[" in document type content', I)
          else
            InSubset := True;
        ']':
          if InSubset then
            InSubset := False
          else
            FailAt(xecWrite, 'Unexpected "]" in document type content', I);
        '<':
          if InSubset and (I + 3 < Len) and (P[I + 1] = '!') and (P[I + 2] = '-') and
            (P[I + 3] = '-') then
          begin
            Pos := FindSeq(P + I + 4, Len - I - 4, '-->');
            if Pos < 0 then
              FailAt(xecWrite, 'Unterminated comment in document type content', I);
            Inc(I, 4 + Pos + 2);
          end
          else if InSubset and (I + 1 < Len) and (P[I + 1] = '?') then
          begin
            Pos := FindSeq(P + I + 2, Len - I - 2, '?>');
            if Pos < 0 then
              FailAt(xecWrite, 'Unterminated processing instruction in document type content', I);
            Inc(I, 2 + Pos + 1);
          end
          else if not InSubset then
            FailAt(xecWrite, 'Unexpected "<" in document type content', I);
        '>':
          if not InSubset then
            FailAt(xecWrite, 'Unexpected ">" in document type content', I);
      else
        ;
      end;
      Inc(I);
    end;
    if InSubset then
      FailAt(xecWrite, 'Unterminated internal subset in document type content', Len);
    BeforeTopLevel;
    AppendLit('<!DOCTYPE ');
    AppendStr(Name);
    Emit(P, Len, emRaw, 'document type declaration');
    AppendLit('>');
    FHasDocType := True;
  except
    Rollback(S);
    raise;
  end;
  AfterCall;
end;

procedure TLandrixXmlWriter.Base64(const Buffer; Size: Integer);
var
  S: TLandrixXmlWriterSnapshot;
  Src: PAnsiChar;
begin
  CheckUsable;
  if Size < 0 then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'Negative base64 input size');
  if (Size = 0) and (FElemCount > 0) then
    Exit;
  TakeSnapshot(S);
  try
    if FElemCount = 0 then
      Fail(xecInvalidOperation, 'Base64 content is only allowed inside an element');
    BeforeText;
    Src := PAnsiChar(@Buffer);
    LandrixXmlBase64Encode(Src^, Size, FBuf);
  except
    Rollback(S);
    raise;
  end;
  AfterCall;
end;

procedure TLandrixXmlWriter.Base64FromStream(Stream: TStream; Count: Int64);
var
  S: TLandrixXmlWriterSnapshot;
  Filled, Want, N: Integer;
  Remaining: Int64;
  Eof: Boolean;
begin
  CheckUsable;
  if Stream = nil then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'Stream must not be nil');
  if Count < -1 then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'Count must be -1 or >= 0');
  TakeSnapshot(S);
  try
    if FElemCount = 0 then
      Fail(xecInvalidOperation, 'Base64 content is only allowed inside an element');
    if Length(FChunk) < Base64Chunk then
      SetLength(FChunk, Base64Chunk);
    Remaining := Count;
    Eof := False;
    while not Eof do
    begin
      { fill a whole chunk so that padding only appears at the very end }
      Filled := 0;
      while Filled < Base64Chunk do
      begin
        Want := Base64Chunk - Filled;
        if (Remaining >= 0) and (Remaining < Want) then
          Want := Integer(Remaining);
        if Want = 0 then
        begin
          Eof := True;
          Break;
        end;
        { TStream.Read returns Longint, 64 bits on 64-bit POSIX Delphi }
        N := Integer(Stream.Read(FChunk[Filled], Want));
        if N <= 0 then
        begin
          if Remaining > 0 then
            Fail(xecInvalidArgument, 'Stream ended before Count bytes were read');
          Eof := True;
          Break;
        end;
        Inc(Filled, N);
        if Remaining >= 0 then
          Dec(Remaining, N);
      end;
      if Filled > 0 then
      begin
        BeforeText;
        LandrixXmlBase64Encode(FChunk[0], Filled, FBuf);
        AfterCall;
      end;
    end;
  except
    Rollback(S);
    raise;
  end;
  AfterCall;
end;

{ --- value variants --------------------------------------------------------- }

procedure TLandrixXmlWriter.Attribute(const QName: TLandrixXmlUtf8; const Value: string);
begin
  DoAttribute(QName, LandrixXmlStringToUtf8(Value));
end;

procedure TLandrixXmlWriter.AttributeUtf8(const QName, Value: TLandrixXmlUtf8);
begin
  DoAttribute(QName, Value);
end;

procedure TLandrixXmlWriter.AttributeW(const QName: TLandrixXmlUtf8;
  const Value: TLandrixXmlWide);
begin
  DoAttribute(QName, LandrixXmlWideToUtf8(Value));
end;

procedure TLandrixXmlWriter.AttributeNs(const NamespaceUri, Prefix,
  LocalName: TLandrixXmlUtf8; const Value: string);
begin
  DoAttributeNs(NamespaceUri, Prefix, LocalName, LandrixXmlStringToUtf8(Value));
end;

procedure TLandrixXmlWriter.AttributeNsUtf8(const NamespaceUri, Prefix, LocalName,
  Value: TLandrixXmlUtf8);
begin
  DoAttributeNs(NamespaceUri, Prefix, LocalName, Value);
end;

procedure TLandrixXmlWriter.AttributeNsW(const NamespaceUri, Prefix,
  LocalName: TLandrixXmlUtf8; const Value: TLandrixXmlWide);
begin
  DoAttributeNs(NamespaceUri, Prefix, LocalName, LandrixXmlWideToUtf8(Value));
end;

procedure TLandrixXmlWriter.Element(const QName: TLandrixXmlUtf8; const Value: string);
begin
  DoElement(QName, LandrixXmlStringToUtf8(Value));
end;

procedure TLandrixXmlWriter.ElementUtf8(const QName, Value: TLandrixXmlUtf8);
begin
  DoElement(QName, Value);
end;

procedure TLandrixXmlWriter.ElementW(const QName: TLandrixXmlUtf8;
  const Value: TLandrixXmlWide);
begin
  DoElement(QName, LandrixXmlWideToUtf8(Value));
end;

procedure TLandrixXmlWriter.ElementNs(const NamespaceUri, Prefix,
  LocalName: TLandrixXmlUtf8; const Value: string);
begin
  DoElementNs(NamespaceUri, Prefix, LocalName, LandrixXmlStringToUtf8(Value));
end;

procedure TLandrixXmlWriter.ElementNsUtf8(const NamespaceUri, Prefix, LocalName,
  Value: TLandrixXmlUtf8);
begin
  DoElementNs(NamespaceUri, Prefix, LocalName, Value);
end;

procedure TLandrixXmlWriter.ElementNsW(const NamespaceUri, Prefix,
  LocalName: TLandrixXmlUtf8; const Value: TLandrixXmlWide);
begin
  DoElementNs(NamespaceUri, Prefix, LocalName, LandrixXmlWideToUtf8(Value));
end;

procedure TLandrixXmlWriter.Text(const Value: string);
begin
  DoText(LandrixXmlStringToUtf8(Value));
end;

procedure TLandrixXmlWriter.TextUtf8(const Value: TLandrixXmlUtf8);
begin
  DoText(Value);
end;

procedure TLandrixXmlWriter.TextW(const Value: TLandrixXmlWide);
begin
  DoText(LandrixXmlWideToUtf8(Value));
end;

procedure TLandrixXmlWriter.CData(const Value: string);
begin
  DoCData(LandrixXmlStringToUtf8(Value));
end;

procedure TLandrixXmlWriter.CDataUtf8(const Value: TLandrixXmlUtf8);
begin
  DoCData(Value);
end;

procedure TLandrixXmlWriter.CDataW(const Value: TLandrixXmlWide);
begin
  DoCData(LandrixXmlWideToUtf8(Value));
end;

procedure TLandrixXmlWriter.Comment(const Value: string);
begin
  DoComment(LandrixXmlStringToUtf8(Value));
end;

procedure TLandrixXmlWriter.CommentUtf8(const Value: TLandrixXmlUtf8);
begin
  DoComment(Value);
end;

procedure TLandrixXmlWriter.CommentW(const Value: TLandrixXmlWide);
begin
  DoComment(LandrixXmlWideToUtf8(Value));
end;

procedure TLandrixXmlWriter.ProcessingInstruction(const Target: TLandrixXmlUtf8;
  const Data: string);
begin
  DoProcessingInstruction(Target, LandrixXmlStringToUtf8(Data));
end;

procedure TLandrixXmlWriter.ProcessingInstructionUtf8(const Target, Data: TLandrixXmlUtf8);
begin
  DoProcessingInstruction(Target, Data);
end;

procedure TLandrixXmlWriter.ProcessingInstructionW(const Target: TLandrixXmlUtf8;
  const Data: TLandrixXmlWide);
begin
  DoProcessingInstruction(Target, LandrixXmlWideToUtf8(Data));
end;

{ --- results ------------------------------------------------------------------ }

function TLandrixXmlWriter.AsUtf8: TLandrixXmlUtf8;
begin
  CheckResult;
  Result := FBuf.AsUtf8;
end;

function TLandrixXmlWriter.AsW: TLandrixXmlWide;
begin
  Result := LandrixXmlUtf8ToWide(AsUtf8);
end;

function TLandrixXmlWriter.AsString: string;
begin
  Result := LandrixXmlUtf8ToString(AsUtf8);
end;

procedure TLandrixXmlWriter.CheckResult;
begin
  if FStream <> nil then
    raise ELandrixXmlError.CreateCode(xecInvalidOperation,
      'The result is only available when writing to memory');
  if not FFinished then
    raise ELandrixXmlError.CreateCode(xecInvalidOperation,
      'The result is only available after EndDocument');
end;

procedure TLandrixXmlWriter.SaveToStream(Stream: TStream);
begin
  CheckResult;
  FBuf.WriteToStream(Stream);
end;

procedure TLandrixXmlWriter.SaveToFile(const FileName: string);
var
  F: TFileStream;
begin
  CheckResult;
  F := TFileStream.Create(FileName, fmCreate);
  try
    FBuf.WriteToStream(F);
  finally
    F.Free;
  end;
end;

end.
