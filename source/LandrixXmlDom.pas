{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Document object model built on TLandrixXmlReader and serialized with
  TLandrixXmlWriter.

  Usage:
    Doc := TLandrixXmlDocument.Create;
    try
      Doc.LoadFromFile('bill.x86');
      Item := Doc.Root.FindChild(GaebNs, 'Award');
      ... Item.ChildText(GaebNs, 'Description'), Item.AttributeValue('', 'ID')
      Doc.Root.AddElement('Remark').Text := 'checked';
      Doc.SaveToFile('out.x86');
    finally
      Doc.Free;
    end;

  Rules (see PLAN.md decision log):
  - One public node class; NodeType tells the kind. Reading members return
    ''/nil/0 on node types they do not apply to, changing members raise
    xecInvalidOperation. (Internally, elements, the document, PIs and the
    DOCTYPE are instances of a descendant that holds names, children and
    attributes, so the many text nodes stay small.)
  - The document is a node: its children are comments, PIs, the DOCTYPE and
    the root element in source order. Root is the document element.
  - Names are interned per document. FindChild(NamespaceUri, LocalName)
    matches namespace and local name (NamespaceUri '' = no namespace);
    FindChildLocal ignores the namespace. Matching is case-sensitive.
  - Attributes keep their source order, xmlns declarations included.
  - Every node knows the Line and Column where it started (0 for nodes
    created through the API).
  - Names passed in are UTF-8 (TLandrixXmlUtf8). Text comes in three
    variants: ...Utf8, ...W (TLandrixXmlWide) and native string.
  - Element names created with a QName resolve the prefix at creation time.
    AddElement with a namespace URI declares the prefix on the new element
    when necessary (xmlns="" for a no-namespace element under a default
    namespace); moving a node with AppendChild/InsertChild adds the
    declarations it needs at its new place. A declaration that would give a
    prefix already used by the element or its attributes another namespace
    is rejected. A default namespace declared later on an element created
    without namespace (xmlns="..." set at the end) is allowed: the node keeps
    NamespaceUri '' until the document is saved and reloaded.
  - Values are checked for valid UTF-8 when they are set; XML rules (e.g.
    "--" in comments, "]]>" in CDATA, control characters) are checked when
    the document is saved.
  - Removing children from the front one by one is O(n) per call; use Clear
    or remove from the end for large lists.
  - The document owns every node, also detached ones. Remove (or Free)
    deletes a node with its subtree, Detach only unlinks it. Freeing and
    serializing never recurse, so deep trees are safe.
  - WhitespaceMode = xwmDropBetweenElements drops white-space-only text in
    elements that have no other text, unless xml:space="preserve" applies.
    It is lossy: in <p><span>A</span> <span>B</span></p> the space between
    the spans is dropped. The default keeps everything. AppendFromReader
    does not know about xml:space on ancestors outside the subtree.
  - Saving writes the infoset: a reloaded document has the same nodes, but
    not necessarily the same bytes (quotes, references, line ends). }

unit LandrixXmlDom;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  Classes,
  LandrixXmlBase,
  LandrixXmlEncoding,
  LandrixXmlReader,
  LandrixXmlWriter;

type
  { Append-only: never reorder or remove values. }
  TLandrixXmlNodeType = (
    xntDocument,
    xntElement,
    xntText,
    xntCData,
    xntComment,
    xntProcessingInstruction,
    xntDocumentType
  );

  TLandrixXmlWhitespaceMode = (xwmPreserve, xwmDropBetweenElements);

  { Interned name, shared by all nodes and attributes of a document. }
  TLandrixXmlName = class
  private
    FPrefix: TLandrixXmlUtf8;
    FLocalName: TLandrixXmlUtf8;
    FNamespaceUri: TLandrixXmlUtf8;
    FQualifiedName: TLandrixXmlUtf8;
    FExpandedId: Integer;
    FHash: Cardinal;
  public
    property Prefix: TLandrixXmlUtf8 read FPrefix;
    property LocalName: TLandrixXmlUtf8 read FLocalName;
    property NamespaceUri: TLandrixXmlUtf8 read FNamespaceUri;
    property QualifiedName: TLandrixXmlUtf8 read FQualifiedName;
    { equal for all names with the same namespace URI and local name }
    property ExpandedId: Integer read FExpandedId;
  end;

  TLandrixXmlNameTable = class
  private
    FNames: TList;          { owns TLandrixXmlName }
    FSlots: array of Integer;
    FExpanded: TList;       { first name of each expanded id }
    FExpSlots: array of Integer;
    procedure Grow;
    procedure GrowExpanded;
  public
    constructor Create;
    destructor Destroy; override;
    function Intern(PrefixP: PAnsiChar; PrefixLen: Integer; LocalP: PAnsiChar;
      LocalLen: Integer; UriP: PAnsiChar; UriLen: Integer): TLandrixXmlName;
    { -1 if no node of the document has ever used this expanded name }
    function FindExpanded(UriP: PAnsiChar; UriLen: Integer; LocalP: PAnsiChar;
      LocalLen: Integer): Integer;
  end;

  TLandrixXmlAttribute = record
    Name: TLandrixXmlName;
    Value: TLandrixXmlUtf8;
  end;

  TLandrixXmlDocument = class;
  TLandrixXmlContainerNode = class;

  { Text, CDATA and comment nodes are instances of this class itself. }
  TLandrixXmlNode = class
  private
    { Field order chosen for size (pointers, Integers, then small fields):
      a document holds millions of nodes. Do not append fields casually. }
    FDocument: TLandrixXmlDocument;
    FParent: TLandrixXmlContainerNode;
    FValue: TLandrixXmlUtf8;
    { position in the parent; without parent the slot in the document's
      list of detached nodes, -1 if not listed there }
    FIndex: Integer;
    FLine: Integer;
    FColumn: Integer;
    FNodeType: TLandrixXmlNodeType;
    FIsEmpty: Boolean;
    FIsWhitespace: Boolean;
    function GetParent: TLandrixXmlNode;
    function GetIndexInParent: Integer;
    function GetChildCount: Integer;
    function GetAttributeCount: Integer;
    function GetChild(Index: Integer): TLandrixXmlNode;
    function GetFirstChild: TLandrixXmlNode;
    function GetLastChild: TLandrixXmlNode;
    function GetNextSibling: TLandrixXmlNode;
    function GetPreviousSibling: TLandrixXmlNode;
    function GetNameUtf8: TLandrixXmlUtf8;
    function GetPrefixUtf8: TLandrixXmlUtf8;
    function GetLocalNameUtf8: TLandrixXmlUtf8;
    function GetNamespaceUriUtf8: TLandrixXmlUtf8;
    function GetValueUtf8: TLandrixXmlUtf8;
    procedure SetValueUtf8(const Value: TLandrixXmlUtf8);
    function GetValueW: TLandrixXmlWide;
    procedure SetValueW(const Value: TLandrixXmlWide);
    function GetValue: string;
    procedure SetValue(const Value: string);
    function GetTextUtf8: TLandrixXmlUtf8;
    procedure SetTextUtf8(const Value: TLandrixXmlUtf8);
    function GetTextW: TLandrixXmlWide;
    procedure SetTextW(const Value: TLandrixXmlWide);
    function GetText: string;
    procedure SetText(const Value: string);
    procedure CheckElement(const Operation: string);
    procedure CheckContainer(const Operation: string);
    procedure CheckAttrIndex(Index: Integer);
    procedure Unlink;
    procedure FreeChildren;
    procedure EnsureDeclarations;
  public
    { Internal: nodes are created by the document and by AddElement & co.
      Raises xecInvalidArgument when the class does not fit the node type. }
    constructor CreateNode(ADocument: TLandrixXmlDocument; ANodeType: TLandrixXmlNodeType);
    { Unlinks the node from its parent and frees it with its subtree. }
    destructor Destroy; override;

    property NodeType: TLandrixXmlNodeType read FNodeType;
    property Document: TLandrixXmlDocument read FDocument;
    property Parent: TLandrixXmlNode read GetParent;
    { position among the parent's children, -1 without parent }
    property IndexInParent: Integer read GetIndexInParent;
    property ChildCount: Integer read GetChildCount;
    property Children[Index: Integer]: TLandrixXmlNode read GetChild; default;
    property FirstChild: TLandrixXmlNode read GetFirstChild;
    property LastChild: TLandrixXmlNode read GetLastChild;
    property NextSibling: TLandrixXmlNode read GetNextSibling;
    property PreviousSibling: TLandrixXmlNode read GetPreviousSibling;
    function IsElement: Boolean;
    function FirstChildElement: TLandrixXmlNode;
    function NextSiblingElement: TLandrixXmlNode;
    { 1-based position in the source, 0 for nodes created through the API }
    property Line: Integer read FLine;
    property Column: Integer read FColumn;
    { element written as <x/> in the source }
    property IsEmptyElement: Boolean read FIsEmpty;

    { Qualified name of an element, target of a PI, name of the DOCTYPE. }
    property NameUtf8: TLandrixXmlUtf8 read GetNameUtf8;
    function NameW: TLandrixXmlWide;
    function Name: string;
    property PrefixUtf8: TLandrixXmlUtf8 read GetPrefixUtf8;
    function Prefix: string;
    property LocalNameUtf8: TLandrixXmlUtf8 read GetLocalNameUtf8;
    function LocalNameW: TLandrixXmlWide;
    function LocalName: string;
    property NamespaceUriUtf8: TLandrixXmlUtf8 read GetNamespaceUriUtf8;
    function NamespaceUriW: TLandrixXmlWide;
    function NamespaceUri: string;

    { Content of text, CDATA, comment, PI (data) and DOCTYPE (everything
      after the name) nodes. }
    property ValueUtf8: TLandrixXmlUtf8 read GetValueUtf8 write SetValueUtf8;
    property ValueW: TLandrixXmlWide read GetValueW write SetValueW;
    property Value: string read GetValue write SetValue;
    { Element/document: all descendant text and CDATA (no comments, no PIs);
      setting replaces all children by one text node. Other nodes: Value. }
    property TextUtf8: TLandrixXmlUtf8 read GetTextUtf8 write SetTextUtf8;
    property TextW: TLandrixXmlWide read GetTextW write SetTextW;
    property Text: string read GetText write SetText;

    { --- attributes (elements) --- }
    property AttributeCount: Integer read GetAttributeCount;
    function AttributeNameUtf8(Index: Integer): TLandrixXmlUtf8;
    function AttributePrefixUtf8(Index: Integer): TLandrixXmlUtf8;
    function AttributeLocalNameUtf8(Index: Integer): TLandrixXmlUtf8;
    function AttributeNamespaceUriUtf8(Index: Integer): TLandrixXmlUtf8;
    function AttributeValueUtf8(Index: Integer): TLandrixXmlUtf8; overload;
    function AttributeValueW(Index: Integer): TLandrixXmlWide; overload;
    function AttributeValue(Index: Integer): string; overload;
    function IsNamespaceDeclaration(Index: Integer): Boolean;
    { by namespace URI and local name ('' = no namespace); -1 / '' when
      missing }
    function AttributeIndex(const NamespaceUri, LocalName: TLandrixXmlUtf8): Integer;
    function HasAttribute(const NamespaceUri, LocalName: TLandrixXmlUtf8): Boolean;
    function AttributeValueUtf8(const NamespaceUri, LocalName: TLandrixXmlUtf8): TLandrixXmlUtf8; overload;
    function AttributeValueW(const NamespaceUri, LocalName: TLandrixXmlUtf8): TLandrixXmlWide; overload;
    function AttributeValue(const NamespaceUri, LocalName: TLandrixXmlUtf8): string; overload;
    function TryAttributeValueUtf8(const NamespaceUri, LocalName: TLandrixXmlUtf8;
      out Value: TLandrixXmlUtf8): Boolean;
    function TryAttributeValueW(const NamespaceUri, LocalName: TLandrixXmlUtf8;
      out Value: TLandrixXmlWide): Boolean;
    function TryAttributeValue(const NamespaceUri, LocalName: TLandrixXmlUtf8;
      out Value: string): Boolean;
    { QName "local" (no namespace) or "prefix:local" (prefix declared in
      scope); "xmlns"/"xmlns:p" declare a namespace. Replaces the value of
      an existing attribute with the same expanded name (order kept). }
    procedure SetAttributeUtf8(const QName, Value: TLandrixXmlUtf8);
    procedure SetAttributeW(const QName: TLandrixXmlUtf8; const Value: TLandrixXmlWide);
    procedure SetAttribute(const QName: TLandrixXmlUtf8; const Value: string);
    { Declares Prefix on this element when it is not bound to NamespaceUri. }
    procedure SetAttributeNsUtf8(const NamespaceUri, Prefix, LocalName, Value: TLandrixXmlUtf8);
    function RemoveAttribute(const NamespaceUri, LocalName: TLandrixXmlUtf8): Boolean;
    procedure RemoveAttributeAt(Index: Integer);
    procedure ClearAttributes;

    { --- namespaces --- }
    procedure DeclareNamespace(const Prefix, NamespaceUri: TLandrixXmlUtf8);
    { namespace bound to Prefix ('' = default) at this node }
    function LookupNamespace(const Prefix: TLandrixXmlUtf8; out NamespaceUri: TLandrixXmlUtf8): Boolean;

    { --- searching (direct children unless stated) --- }
    function FindChild(const NamespaceUri, LocalName: TLandrixXmlUtf8): TLandrixXmlNode;
    function FindChildLocal(const LocalName: TLandrixXmlUtf8): TLandrixXmlNode;
    { appends the matches to List (not owned), returns their number }
    function FindChildren(const NamespaceUri, LocalName: TLandrixXmlUtf8; List: TList): Integer;
    { first match in document order below this node }
    function FindDescendant(const NamespaceUri, LocalName: TLandrixXmlUtf8): TLandrixXmlNode;
    { text of the first matching child element, '' when missing }
    function ChildTextUtf8(const NamespaceUri, LocalName: TLandrixXmlUtf8): TLandrixXmlUtf8;
    function ChildTextW(const NamespaceUri, LocalName: TLandrixXmlUtf8): TLandrixXmlWide;
    function ChildText(const NamespaceUri, LocalName: TLandrixXmlUtf8): string;
    { diagnostic path like /rsm:Invoice/ram:Line[2]/ram:Name }
    function NodePathUtf8: TLandrixXmlUtf8;
    function NodePath: string;

    { --- building --- }
    function AddElement(const NamespaceUri, Prefix, LocalName: TLandrixXmlUtf8): TLandrixXmlNode; overload;
    function AddElement(const QName: TLandrixXmlUtf8): TLandrixXmlNode; overload;
    function AddTextUtf8(const Value: TLandrixXmlUtf8): TLandrixXmlNode;
    function AddTextW(const Value: TLandrixXmlWide): TLandrixXmlNode;
    function AddText(const Value: string): TLandrixXmlNode;
    function AddCDataUtf8(const Value: TLandrixXmlUtf8): TLandrixXmlNode;
    function AddCDataW(const Value: TLandrixXmlWide): TLandrixXmlNode;
    function AddCData(const Value: string): TLandrixXmlNode;
    function AddCommentUtf8(const Value: TLandrixXmlUtf8): TLandrixXmlNode;
    function AddCommentW(const Value: TLandrixXmlWide): TLandrixXmlNode;
    function AddComment(const Value: string): TLandrixXmlNode;
    function AddProcessingInstruction(const Target, Data: TLandrixXmlUtf8): TLandrixXmlNode;
    { Moves a detached node (or a node from elsewhere in the same document)
      here. }
    procedure AppendChild(Node: TLandrixXmlNode);
    procedure InsertChild(Index: Integer; Node: TLandrixXmlNode);
    { Unlinks the node; the document still owns it. }
    procedure Detach;
    { Same as Free. }
    procedure Remove;
    { Frees all children. }
    procedure Clear; virtual;

    { Reads the element the reader is positioned on (xttStartElement) with
      its subtree and appends it as a child; the reader stops on the
      matching end tag. Missing namespace declarations are added to the new
      element. Returns the new element. }
    function AppendFromReader(Reader: TLandrixXmlReader): TLandrixXmlNode;
    { Writes the node with its subtree; for an element below another
      element the namespace declarations in scope are repeated on it. }
    procedure WriteTo(Writer: TLandrixXmlWriter);
  end;

  { Internal: elements, the document, PIs and the DOCTYPE. Work with
    TLandrixXmlNode; this class only adds the fields text nodes do not
    need. }
  TLandrixXmlContainerNode = class(TLandrixXmlNode)
  private
    FName: TLandrixXmlName;
    FChildren: array of TLandrixXmlNode;
    FAttrs: array of TLandrixXmlAttribute;
    FChildCount: Integer;
    FAttrCount: Integer;
    procedure InsertAt(Index: Integer; Node: TLandrixXmlNode);
    function NewChild(NodeType: TLandrixXmlNodeType): TLandrixXmlNode;
    procedure AddAttr(Name: TLandrixXmlName; const Value: TLandrixXmlUtf8);
    function DeclaredPrefixIndex(const Prefix: TLandrixXmlUtf8): Integer;
  end;

  TLandrixXmlDocument = class(TLandrixXmlContainerNode)
  private
    FNames: TLandrixXmlNameTable;
    FDetachedNodes: TList;
    FWhitespaceMode: TLandrixXmlWhitespaceMode;
    FKeepComments: Boolean;
    FKeepProcessingInstructions: Boolean;
    FMaxDepth: Integer;
    FFallbackEncoding: TLandrixXmlEncoding;
    FLatin1AsWindows1252: Boolean;
    FVersion: TLandrixXmlUtf8;
    FStandalone: TLandrixXmlUtf8;
    FSourceEncoding: TLandrixXmlEncoding;
    FDeclaredEncoding: TLandrixXmlUtf8;
    FHadBom: Boolean;
    FIndent: Boolean;
    FLineBreak: TLandrixXmlLineBreak;
    FWriteBom: Boolean;
    FWriteDeclaration: Boolean;
    function GetRoot: TLandrixXmlNode;
    procedure SetMaxDepth(Value: Integer);
    procedure SetStandalone(const Value: TLandrixXmlUtf8);
    function Build(Reader: TLandrixXmlReader; Target: TLandrixXmlNode;
      Subtree: Boolean): TLandrixXmlNode;
    procedure LoadWith(Reader: TLandrixXmlReader);
    procedure PrepareReader(Reader: TLandrixXmlReader);
    procedure ConfigureWriter(Writer: TLandrixXmlWriter);
  public
    constructor Create;
    destructor Destroy; override;
    { Frees all nodes and resets the document metadata (options stay). }
    procedure Clear; override;

    { A failed load leaves the document empty. }
    procedure LoadFromFile(const FileName: string);
    procedure LoadFromStream(Stream: TStream);
    procedure LoadFromBuffer(const Data; Size: Integer);
    procedure LoadFromUtf8(const S: TLandrixXmlUtf8);
    procedure LoadFromString(const S: string);

    procedure SaveToFile(const FileName: string);
    procedure SaveToStream(Stream: TStream);
    function SaveToUtf8: TLandrixXmlUtf8;
    function SaveToString: string;
    { Writes all nodes; the caller calls Writer.EndDocument. }
    procedure SaveToWriter(Writer: TLandrixXmlWriter);

    property Root: TLandrixXmlNode read GetRoot;
    property Names: TLandrixXmlNameTable read FNames;

    { load options }
    property WhitespaceMode: TLandrixXmlWhitespaceMode read FWhitespaceMode write FWhitespaceMode;
    property KeepComments: Boolean read FKeepComments write FKeepComments;
    property KeepProcessingInstructions: Boolean read FKeepProcessingInstructions
      write FKeepProcessingInstructions;
    property MaxDepth: Integer read FMaxDepth write SetMaxDepth;
    property FallbackEncoding: TLandrixXmlEncoding read FFallbackEncoding write FFallbackEncoding;
    property Latin1AsWindows1252: Boolean read FLatin1AsWindows1252 write FLatin1AsWindows1252;

    { metadata of the last load; Standalone '', 'yes' or 'no' is also
      written when saving }
    property Version: TLandrixXmlUtf8 read FVersion;
    property Standalone: TLandrixXmlUtf8 read FStandalone write SetStandalone;
    property SourceEncoding: TLandrixXmlEncoding read FSourceEncoding;
    property DeclaredEncoding: TLandrixXmlUtf8 read FDeclaredEncoding;
    property HadBom: Boolean read FHadBom;

    { save options }
    property Indent: Boolean read FIndent write FIndent;
    property LineBreak: TLandrixXmlLineBreak read FLineBreak write FLineBreak;
    property WriteBom: Boolean read FWriteBom write FWriteBom;
    property WriteDeclaration: Boolean read FWriteDeclaration write FWriteDeclaration;
  end;

implementation

{ --- helpers ---------------------------------------------------------------- }

function SpanStr(P: PAnsiChar; Len: Integer): TLandrixXmlUtf8;
begin
  Result := '';
  if Len > 0 then
    SetString(Result, P, Len);
end;

function SameBuf(P1: PAnsiChar; Len1: Integer; const S: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  Result := Len1 = Length(S);
  I := 0;
  while Result and (I < Len1) do
  begin
    Result := P1[I] = PAnsiChar(S)[I];
    Inc(I);
  end;
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

procedure RaiseOp(const Msg: string);
begin
  raise ELandrixXmlError.CreateCode(xecInvalidOperation, Msg);
end;

procedure RaiseArg(const Msg: string);
begin
  raise ELandrixXmlError.CreateCode(xecInvalidArgument, Msg);
end;

procedure RaiseNs(const Msg: string);
begin
  raise ELandrixXmlError.CreateCode(xecNamespace, Msg);
end;

procedure CheckUtf8(const S: TLandrixXmlUtf8);
var
  Bad: Integer;
begin
  if not LandrixXmlValidateUtf8(S, Bad) then
    raise ELandrixXmlError.CreateAt(xecInvalidUnicode, 'Invalid UTF-8 byte sequence', 0, 0, Bad);
end;

{ Checks an XML name with namespace rules; returns the colon position. }
function CheckQName(const QName: TLandrixXmlUtf8): Integer;
var
  I: Integer;
begin
  if LandrixXmlCheckName(PAnsiChar(QName), Length(QName)) >= 0 then
    RaiseArg('Invalid XML name "' + LandrixXmlEscapeForMessage(QName, 60) + '"');
  Result := -1;
  for I := 0 to Length(QName) - 1 do
    if PAnsiChar(QName)[I] = ':' then
    begin
      if Result >= 0 then
        RaiseNs('Qualified name with more than one colon: "' +
          LandrixXmlEscapeForMessage(QName, 60) + '"');
      Result := I;
    end;
  if (Result = 0) or (Result = Length(QName) - 1) or ((Result > 0) and
    (LandrixXmlCheckName(PAnsiChar(QName) + Result + 1, Length(QName) - Result - 1) >= 0)) then
    RaiseNs('Invalid qualified name "' + LandrixXmlEscapeForMessage(QName, 60) + '"');
end;

procedure CheckNcName(const Name: TLandrixXmlUtf8);
begin
  if CheckQName(Name) >= 0 then
    RaiseNs('Name must not contain a colon: "' + LandrixXmlEscapeForMessage(Name, 60) + '"');
end;

const
  ContainerTypes = [xntDocument, xntElement, xntProcessingInstruction, xntDocumentType];

{ The node as a container; nil for text, CDATA and comment nodes. }
function AsContainer(N: TLandrixXmlNode): TLandrixXmlContainerNode;
begin
  if N is TLandrixXmlContainerNode then
    Result := TLandrixXmlContainerNode(N)
  else
    Result := nil;
end;

{ Checked cast for code paths that have already checked the node type. }
function Cont(N: TLandrixXmlNode): TLandrixXmlContainerNode;
begin
  if not (N is TLandrixXmlContainerNode) then
    raise ELandrixXmlError.CreateCode(xecGeneral, 'Internal error: node without children');
  Result := TLandrixXmlContainerNode(N);
end;

{ Name of an element, PI or DOCTYPE; nil for other nodes. }
function NameOf(N: TLandrixXmlNode): TLandrixXmlName;
begin
  if N is TLandrixXmlContainerNode then
    Result := TLandrixXmlContainerNode(N).FName
  else
    Result := nil;
end;

function NewNodeOf(Doc: TLandrixXmlDocument; NodeType: TLandrixXmlNodeType): TLandrixXmlNode;
begin
  if NodeType in ContainerTypes then
    Result := TLandrixXmlContainerNode.CreateNode(Doc, NodeType)
  else
    Result := TLandrixXmlNode.CreateNode(Doc, NodeType);
end;

{ O(1) removal from the document's list of detached nodes: the last entry
  takes the free slot. }
procedure RemoveDetached(Node: TLandrixXmlNode);
var
  List: TList;
  Last: TLandrixXmlNode;
begin
  List := Node.FDocument.FDetachedNodes;
  Last := TLandrixXmlNode(List[List.Count - 1]);
  List[Node.FIndex] := Last;
  Last.FIndex := Node.FIndex;
  List.Delete(List.Count - 1);
  Node.FIndex := -1;
end;

{ first element child (the root element of a document) }
function GetRoot_(Doc: TLandrixXmlNode): TLandrixXmlNode;
var
  C: TLandrixXmlContainerNode;
  I: Integer;
begin
  Result := nil;
  C := AsContainer(Doc);
  if C = nil then
    Exit;
  for I := 0 to C.FChildCount - 1 do
    if C.FChildren[I].FNodeType = xntElement then
    begin
      Result := C.FChildren[I];
      Exit;
    end;
end;

{ --- name table ------------------------------------------------------------ }

function HashTriple(PrefixP: PAnsiChar; PrefixLen: Integer; LocalP: PAnsiChar;
  LocalLen: Integer; UriP: PAnsiChar; UriLen: Integer): Cardinal;
var
  Sep: AnsiChar;
begin
  Sep := #0;
  Result := LandrixXmlHashBytes(PrefixP, PrefixLen, LandrixXmlHashSeed);
  Result := LandrixXmlHashBytes(@Sep, 1, Result);
  Result := LandrixXmlHashBytes(LocalP, LocalLen, Result);
  Result := LandrixXmlHashBytes(@Sep, 1, Result);
  Result := LandrixXmlHashBytes(UriP, UriLen, Result);
end;

function HashExpanded(UriP: PAnsiChar; UriLen: Integer; LocalP: PAnsiChar;
  LocalLen: Integer): Cardinal;
var
  Sep: AnsiChar;
begin
  Sep := #0;
  Result := LandrixXmlHashBytes(UriP, UriLen, LandrixXmlHashSeed);
  Result := LandrixXmlHashBytes(@Sep, 1, Result);
  Result := LandrixXmlHashBytes(LocalP, LocalLen, Result);
end;

constructor TLandrixXmlNameTable.Create;
var
  I: Integer;
begin
  inherited Create;
  FNames := TList.Create;
  FExpanded := TList.Create;
  SetLength(FSlots, 256);
  for I := 0 to Integer(High(FSlots)) do
    FSlots[I] := -1;
  SetLength(FExpSlots, 256);
  for I := 0 to Integer(High(FExpSlots)) do
    FExpSlots[I] := -1;
end;

destructor TLandrixXmlNameTable.Destroy;
var
  I: Integer;
begin
  if FNames <> nil then
    for I := 0 to Integer(FNames.Count) - 1 do
      TObject(FNames[I]).Free;
  FNames.Free;
  FExpanded.Free;
  inherited Destroy;
end;

procedure TLandrixXmlNameTable.Grow;
var
  I, Size, Slot: Integer;
begin
  Size := Integer(Length(FSlots)) * 2;
  SetLength(FSlots, Size);
  for I := 0 to Size - 1 do
    FSlots[I] := -1;
  for I := 0 to Integer(FNames.Count) - 1 do
  begin
    Slot := Integer(TLandrixXmlName(FNames[I]).FHash and Cardinal(Size - 1));
    while FSlots[Slot] >= 0 do
      Slot := (Slot + 1) and (Size - 1);
    FSlots[Slot] := I;
  end;
end;

procedure TLandrixXmlNameTable.GrowExpanded;
var
  I, Size, Slot: Integer;
  N: TLandrixXmlName;
begin
  Size := Integer(Length(FExpSlots)) * 2;
  SetLength(FExpSlots, Size);
  for I := 0 to Size - 1 do
    FExpSlots[I] := -1;
  for I := 0 to Integer(FExpanded.Count) - 1 do
  begin
    N := TLandrixXmlName(FExpanded[I]);
    Slot := Integer(HashExpanded(PAnsiChar(N.FNamespaceUri), Length(N.FNamespaceUri),
      PAnsiChar(N.FLocalName), Length(N.FLocalName)) and Cardinal(Size - 1));
    while FExpSlots[Slot] >= 0 do
      Slot := (Slot + 1) and (Size - 1);
    FExpSlots[Slot] := I;
  end;
end;

function TLandrixXmlNameTable.FindExpanded(UriP: PAnsiChar; UriLen: Integer;
  LocalP: PAnsiChar; LocalLen: Integer): Integer;
var
  Size, Slot: Integer;
  N: TLandrixXmlName;
begin
  Size := Integer(Length(FExpSlots));
  Slot := Integer(HashExpanded(UriP, UriLen, LocalP, LocalLen) and Cardinal(Size - 1));
  while FExpSlots[Slot] >= 0 do
  begin
    N := TLandrixXmlName(FExpanded[FExpSlots[Slot]]);
    if SameBuf(UriP, UriLen, N.FNamespaceUri) and SameBuf(LocalP, LocalLen, N.FLocalName) then
    begin
      Result := FExpSlots[Slot];
      Exit;
    end;
    Slot := (Slot + 1) and (Size - 1);
  end;
  Result := -1;
end;

function TLandrixXmlNameTable.Intern(PrefixP: PAnsiChar; PrefixLen: Integer;
  LocalP: PAnsiChar; LocalLen: Integer; UriP: PAnsiChar; UriLen: Integer): TLandrixXmlName;
var
  H: Cardinal;
  Size, Slot, ESlot, Id: Integer;
  N: TLandrixXmlName;
begin
  H := HashTriple(PrefixP, PrefixLen, LocalP, LocalLen, UriP, UriLen);
  Size := Integer(Length(FSlots));
  Slot := Integer(H and Cardinal(Size - 1));
  while FSlots[Slot] >= 0 do
  begin
    N := TLandrixXmlName(FNames[FSlots[Slot]]);
    if (N.FHash = H) and SameBuf(LocalP, LocalLen, N.FLocalName) and
      SameBuf(PrefixP, PrefixLen, N.FPrefix) and SameBuf(UriP, UriLen, N.FNamespaceUri) then
    begin
      Result := N;
      Exit;
    end;
    Slot := (Slot + 1) and (Size - 1);
  end;
  N := TLandrixXmlName.Create;
  N.FPrefix := SpanStr(PrefixP, PrefixLen);
  N.FLocalName := SpanStr(LocalP, LocalLen);
  N.FNamespaceUri := SpanStr(UriP, UriLen);
  if PrefixLen > 0 then
    N.FQualifiedName := N.FPrefix + ':' + N.FLocalName
  else
    N.FQualifiedName := N.FLocalName;
  N.FHash := H;
  Id := FindExpanded(UriP, UriLen, LocalP, LocalLen);
  if Id < 0 then
  begin
    Id := Integer(FExpanded.Add(N));
    if 2 * FExpanded.Count > Integer(Length(FExpSlots)) then
      GrowExpanded
    else
    begin
      ESlot := Integer(HashExpanded(UriP, UriLen, LocalP, LocalLen) and
        Cardinal(Integer(Length(FExpSlots)) - 1));
      while FExpSlots[ESlot] >= 0 do
        ESlot := (ESlot + 1) and (Integer(Length(FExpSlots)) - 1);
      FExpSlots[ESlot] := Id;
    end;
  end;
  N.FExpandedId := Id;
  FSlots[Slot] := Integer(FNames.Add(N));
  if 2 * FNames.Count > Integer(Length(FSlots)) then
    Grow;
  Result := N;
end;

{ --- TLandrixXmlNode: life cycle ------------------------------------------------ }

constructor TLandrixXmlNode.CreateNode(ADocument: TLandrixXmlDocument;
  ANodeType: TLandrixXmlNodeType);
begin
  inherited Create;
  FIndex := -1;
  if (ANodeType in ContainerTypes) <> (Self is TLandrixXmlContainerNode) then
    RaiseArg('Nodes are created by the document and the Add... methods');
  FDocument := ADocument;
  FNodeType := ANodeType;
end;

destructor TLandrixXmlNode.Destroy;
begin
  if FParent <> nil then
    Unlink
  else if (FIndex >= 0) and (FDocument <> nil) and (FDocument <> Self) then
    RemoveDetached(Self);
  FreeChildren;
  inherited Destroy;
end;

{ Frees the subtree without recursion: every node is emptied before it is
  freed, so its destructor has nothing left to do. }
procedure TLandrixXmlNode.FreeChildren;
var
  Stack: TList;
  N: TLandrixXmlNode;
  C, NC: TLandrixXmlContainerNode;
  I: Integer;
begin
  C := AsContainer(Self);
  if (C = nil) or (C.FChildCount = 0) then
    Exit;
  Stack := TList.Create;
  try
    for I := 0 to C.FChildCount - 1 do
      Stack.Add(C.FChildren[I]);
    C.FChildCount := 0;
    C.FChildren := nil;
    while Stack.Count > 0 do
    begin
      N := TLandrixXmlNode(Stack[Stack.Count - 1]);
      Stack.Delete(Stack.Count - 1);
      NC := AsContainer(N);
      if NC <> nil then
      begin
        for I := 0 to NC.FChildCount - 1 do
          Stack.Add(NC.FChildren[I]);
        NC.FChildCount := 0;
        NC.FChildren := nil;
      end;
      N.FParent := nil;
      N.FIndex := -1;
      N.Free;
    end;
  finally
    Stack.Free;
  end;
end;

procedure TLandrixXmlNode.Unlink;
var
  P: TLandrixXmlContainerNode;
  I: Integer;
begin
  P := FParent;
  for I := FIndex to P.FChildCount - 2 do
  begin
    P.FChildren[I] := P.FChildren[I + 1];
    P.FChildren[I].FIndex := I;
  end;
  Dec(P.FChildCount);
  P.FChildren[P.FChildCount] := nil;
  FParent := nil;
  FIndex := -1;
end;

procedure TLandrixXmlContainerNode.InsertAt(Index: Integer; Node: TLandrixXmlNode);
var
  I: Integer;
begin
  if FChildCount = Length(FChildren) then
  begin
    if FChildCount < 4 then
      SetLength(FChildren, 4)
    else
      SetLength(FChildren, 2 * FChildCount);
  end;
  for I := FChildCount downto Index + 1 do
  begin
    FChildren[I] := FChildren[I - 1];
    FChildren[I].FIndex := I;
  end;
  FChildren[Index] := Node;
  Node.FIndex := Index;
  Node.FParent := Self;
  Inc(FChildCount);
end;

function TLandrixXmlNode.GetParent: TLandrixXmlNode;
begin
  Result := FParent;
end;

function TLandrixXmlNode.GetChildCount: Integer;
var
  C: TLandrixXmlContainerNode;
begin
  C := AsContainer(Self);
  if C = nil then
    Result := 0
  else
    Result := C.FChildCount;
end;

function TLandrixXmlNode.GetAttributeCount: Integer;
var
  C: TLandrixXmlContainerNode;
begin
  C := AsContainer(Self);
  if C = nil then
    Result := 0
  else
    Result := C.FAttrCount;
end;

function TLandrixXmlNode.GetIndexInParent: Integer;
begin
  if FParent = nil then
    Result := -1
  else
    Result := FIndex;
end;

procedure TLandrixXmlNode.Detach;
begin
  if FNodeType = xntDocument then
    RaiseOp('The document cannot be detached');
  if FParent = nil then
    Exit;
  Unlink;
  FIndex := Integer(FDocument.FDetachedNodes.Add(Self));
end;

procedure TLandrixXmlNode.Remove;
begin
  Free;
end;

procedure TLandrixXmlNode.Clear;
begin
  FreeChildren;
end;

procedure TLandrixXmlNode.InsertChild(Index: Integer; Node: TLandrixXmlNode);
var
  A: TLandrixXmlNode;
  C: TLandrixXmlContainerNode;
begin
  CheckContainer('InsertChild');
  C := Cont(Self);
  if Node = nil then
    RaiseArg('Node must not be nil');
  if Node.FDocument <> FDocument then
    RaiseArg('The node belongs to another document');
  if Node.FNodeType = xntDocument then
    RaiseArg('A document cannot be a child');
  A := Self;
  while A <> nil do
  begin
    if A = Node then
      RaiseArg('A node cannot become its own descendant');
    A := A.FParent;
  end;
  if FNodeType = xntDocument then
  begin
    if Node.FNodeType in [xntText, xntCData] then
      RaiseOp('The document cannot contain text');
    if (Node.FNodeType = xntElement) and (GetRoot_(Self) <> nil) and (GetRoot_(Self) <> Node) then
      RaiseOp('The document already has a root element');
  end
  else if Node.FNodeType = xntDocumentType then
    RaiseOp('A document type declaration belongs to the document');
  { validate first: a failing call changes nothing }
  if Node.FParent = C then
  begin
    if (Index < 0) or (Index > C.FChildCount) then
      RaiseArg('Child index out of range');
    if Node.FIndex < Index then
      Dec(Index);
  end
  else if (Index < 0) or (Index > C.FChildCount) then
    RaiseArg('Child index out of range');
  if Node.FParent <> nil then
    Node.Unlink
  else if Node.FIndex >= 0 then
    RemoveDetached(Node);
  C.InsertAt(Index, Node);
  if Node.FNodeType = xntElement then
    Node.EnsureDeclarations;
end;

procedure TLandrixXmlNode.AppendChild(Node: TLandrixXmlNode);
begin
  InsertChild(GetChildCount, Node);
end;

{ --- navigation ---------------------------------------------------------------- }

function TLandrixXmlNode.GetChild(Index: Integer): TLandrixXmlNode;
var
  C: TLandrixXmlContainerNode;
begin
  C := AsContainer(Self);
  if (C = nil) or (Index < 0) or (Index >= C.FChildCount) then
    RaiseArg('Child index out of range');
  Result := C.FChildren[Index];
end;

function TLandrixXmlNode.GetFirstChild: TLandrixXmlNode;
var
  C: TLandrixXmlContainerNode;
begin
  C := AsContainer(Self);
  if (C <> nil) and (C.FChildCount > 0) then
    Result := C.FChildren[0]
  else
    Result := nil;
end;

function TLandrixXmlNode.GetLastChild: TLandrixXmlNode;
var
  C: TLandrixXmlContainerNode;
begin
  C := AsContainer(Self);
  if (C <> nil) and (C.FChildCount > 0) then
    Result := C.FChildren[C.FChildCount - 1]
  else
    Result := nil;
end;

function TLandrixXmlNode.GetNextSibling: TLandrixXmlNode;
begin
  if (FParent <> nil) and (FIndex < FParent.FChildCount - 1) then
    Result := FParent.FChildren[FIndex + 1]
  else
    Result := nil;
end;

function TLandrixXmlNode.GetPreviousSibling: TLandrixXmlNode;
begin
  if (FParent <> nil) and (FIndex > 0) then
    Result := FParent.FChildren[FIndex - 1]
  else
    Result := nil;
end;

function TLandrixXmlNode.IsElement: Boolean;
begin
  Result := FNodeType = xntElement;
end;

function TLandrixXmlNode.FirstChildElement: TLandrixXmlNode;
begin
  Result := GetRoot_(Self);
end;

function TLandrixXmlNode.NextSiblingElement: TLandrixXmlNode;
var
  I: Integer;
begin
  Result := nil;
  if FParent = nil then
    Exit;
  for I := FIndex + 1 to FParent.FChildCount - 1 do
    if FParent.FChildren[I].FNodeType = xntElement then
    begin
      Result := FParent.FChildren[I];
      Exit;
    end;
end;

{ --- names and values ------------------------------------------------------- }

function TLandrixXmlNode.GetNameUtf8: TLandrixXmlUtf8;
var
  N: TLandrixXmlName;
begin
  N := NameOf(Self);
  if N <> nil then
    Result := N.FQualifiedName
  else
    Result := '';
end;

function TLandrixXmlNode.NameW: TLandrixXmlWide;
begin
  Result := LandrixXmlUtf8ToWide(GetNameUtf8);
end;

function TLandrixXmlNode.Name: string;
begin
  Result := LandrixXmlUtf8ToString(GetNameUtf8);
end;

function TLandrixXmlNode.GetPrefixUtf8: TLandrixXmlUtf8;
var
  N: TLandrixXmlName;
begin
  N := NameOf(Self);
  if N <> nil then
    Result := N.FPrefix
  else
    Result := '';
end;

function TLandrixXmlNode.Prefix: string;
begin
  Result := LandrixXmlUtf8ToString(GetPrefixUtf8);
end;

function TLandrixXmlNode.GetLocalNameUtf8: TLandrixXmlUtf8;
var
  N: TLandrixXmlName;
begin
  N := NameOf(Self);
  if N <> nil then
    Result := N.FLocalName
  else
    Result := '';
end;

function TLandrixXmlNode.LocalNameW: TLandrixXmlWide;
begin
  Result := LandrixXmlUtf8ToWide(GetLocalNameUtf8);
end;

function TLandrixXmlNode.LocalName: string;
begin
  Result := LandrixXmlUtf8ToString(GetLocalNameUtf8);
end;

function TLandrixXmlNode.GetNamespaceUriUtf8: TLandrixXmlUtf8;
var
  N: TLandrixXmlName;
begin
  N := NameOf(Self);
  if N <> nil then
    Result := N.FNamespaceUri
  else
    Result := '';
end;

function TLandrixXmlNode.NamespaceUriW: TLandrixXmlWide;
begin
  Result := LandrixXmlUtf8ToWide(GetNamespaceUriUtf8);
end;

function TLandrixXmlNode.NamespaceUri: string;
begin
  Result := LandrixXmlUtf8ToString(GetNamespaceUriUtf8);
end;

function TLandrixXmlNode.GetValueUtf8: TLandrixXmlUtf8;
begin
  Result := FValue;
end;

procedure TLandrixXmlNode.SetValueUtf8(const Value: TLandrixXmlUtf8);
begin
  if FNodeType in [xntDocument, xntElement] then
    RaiseOp('Elements have no value; use Text');
  CheckUtf8(Value);
  FValue := Value;
  FIsWhitespace := False;
end;

function TLandrixXmlNode.GetValueW: TLandrixXmlWide;
begin
  Result := LandrixXmlUtf8ToWide(FValue);
end;

procedure TLandrixXmlNode.SetValueW(const Value: TLandrixXmlWide);
begin
  SetValueUtf8(LandrixXmlWideToUtf8(Value));
end;

function TLandrixXmlNode.GetValue: string;
begin
  Result := LandrixXmlUtf8ToString(FValue);
end;

procedure TLandrixXmlNode.SetValue(const Value: string);
begin
  SetValueUtf8(LandrixXmlStringToUtf8(Value));
end;

function TLandrixXmlNode.GetTextUtf8: TLandrixXmlUtf8;
var
  Buf: TLandrixXmlBuffer;
  Stack: TList;
  N: TLandrixXmlNode;
  C, NC: TLandrixXmlContainerNode;
  I: Integer;
begin
  if not (FNodeType in [xntDocument, xntElement]) then
  begin
    Result := FValue;
    Exit;
  end;
  C := TLandrixXmlContainerNode(Self);
  if (C.FChildCount = 1) and (C.FChildren[0].FNodeType in [xntText, xntCData]) then
  begin
    Result := C.FChildren[0].FValue;
    Exit;
  end;
  Buf := TLandrixXmlBuffer.Create;
  Stack := TList.Create;
  try
    for I := C.FChildCount - 1 downto 0 do
      Stack.Add(C.FChildren[I]);
    while Stack.Count > 0 do
    begin
      N := TLandrixXmlNode(Stack[Stack.Count - 1]);
      Stack.Delete(Stack.Count - 1);
      if N.FNodeType in [xntText, xntCData] then
        Buf.AppendUtf8(N.FValue)
      else if N.FNodeType = xntElement then
      begin
        NC := TLandrixXmlContainerNode(N);
        for I := NC.FChildCount - 1 downto 0 do
          Stack.Add(NC.FChildren[I]);
      end;
    end;
    Result := Buf.AsUtf8;
  finally
    Stack.Free;
    Buf.Free;
  end;
end;

procedure TLandrixXmlNode.SetTextUtf8(const Value: TLandrixXmlUtf8);
begin
  if FNodeType = xntDocument then
    RaiseOp('The document cannot contain text');
  if FNodeType <> xntElement then
  begin
    SetValueUtf8(Value);
    Exit;
  end;
  CheckUtf8(Value);
  FreeChildren;
  if Value <> '' then
    Cont(Self).NewChild(xntText).FValue := Value;
end;

function TLandrixXmlNode.GetTextW: TLandrixXmlWide;
begin
  Result := LandrixXmlUtf8ToWide(GetTextUtf8);
end;

procedure TLandrixXmlNode.SetTextW(const Value: TLandrixXmlWide);
begin
  SetTextUtf8(LandrixXmlWideToUtf8(Value));
end;

function TLandrixXmlNode.GetText: string;
begin
  Result := LandrixXmlUtf8ToString(GetTextUtf8);
end;

procedure TLandrixXmlNode.SetText(const Value: string);
begin
  SetTextUtf8(LandrixXmlStringToUtf8(Value));
end;

{ --- checks ------------------------------------------------------------------- }

procedure TLandrixXmlNode.CheckElement(const Operation: string);
begin
  if FNodeType <> xntElement then
    RaiseOp(Operation + ' is only possible on elements');
end;

procedure TLandrixXmlNode.CheckContainer(const Operation: string);
begin
  if not (FNodeType in [xntDocument, xntElement]) then
    RaiseOp(Operation + ' is only possible on elements and the document');
end;

procedure TLandrixXmlNode.CheckAttrIndex(Index: Integer);
begin
  if (Index < 0) or (Index >= GetAttributeCount) then
    RaiseArg('Attribute index out of range');
end;

{ --- attributes ------------------------------------------------------------------ }

function TLandrixXmlNode.AttributeNameUtf8(Index: Integer): TLandrixXmlUtf8;
begin
  CheckAttrIndex(Index);
  Result := TLandrixXmlContainerNode(Self).FAttrs[Index].Name.FQualifiedName;
end;

function TLandrixXmlNode.AttributePrefixUtf8(Index: Integer): TLandrixXmlUtf8;
begin
  CheckAttrIndex(Index);
  Result := TLandrixXmlContainerNode(Self).FAttrs[Index].Name.FPrefix;
end;

function TLandrixXmlNode.AttributeLocalNameUtf8(Index: Integer): TLandrixXmlUtf8;
begin
  CheckAttrIndex(Index);
  Result := TLandrixXmlContainerNode(Self).FAttrs[Index].Name.FLocalName;
end;

function TLandrixXmlNode.AttributeNamespaceUriUtf8(Index: Integer): TLandrixXmlUtf8;
begin
  CheckAttrIndex(Index);
  Result := TLandrixXmlContainerNode(Self).FAttrs[Index].Name.FNamespaceUri;
end;

function TLandrixXmlNode.AttributeValueUtf8(Index: Integer): TLandrixXmlUtf8;
begin
  CheckAttrIndex(Index);
  Result := TLandrixXmlContainerNode(Self).FAttrs[Index].Value;
end;

function TLandrixXmlNode.AttributeValueW(Index: Integer): TLandrixXmlWide;
begin
  Result := LandrixXmlUtf8ToWide(AttributeValueUtf8(Index));
end;

function TLandrixXmlNode.AttributeValue(Index: Integer): string;
begin
  Result := LandrixXmlUtf8ToString(AttributeValueUtf8(Index));
end;

function TLandrixXmlNode.IsNamespaceDeclaration(Index: Integer): Boolean;
begin
  CheckAttrIndex(Index);
  Result := TLandrixXmlContainerNode(Self).FAttrs[Index].Name.FNamespaceUri =
    LandrixXmlNamespaceXmlns;
end;

function TLandrixXmlNode.AttributeIndex(const NamespaceUri, LocalName: TLandrixXmlUtf8): Integer;
var
  Id: Integer;
  C: TLandrixXmlContainerNode;
begin
  Result := -1;
  C := AsContainer(Self);
  if (C = nil) or (C.FAttrCount = 0) or (FDocument = nil) then
    Exit;
  Id := FDocument.FNames.FindExpanded(PAnsiChar(NamespaceUri), Length(NamespaceUri),
    PAnsiChar(LocalName), Length(LocalName));
  if Id < 0 then
    Exit;
  for Result := 0 to C.FAttrCount - 1 do
    if C.FAttrs[Result].Name.FExpandedId = Id then
      Exit;
  Result := -1;
end;

function TLandrixXmlNode.HasAttribute(const NamespaceUri, LocalName: TLandrixXmlUtf8): Boolean;
begin
  Result := AttributeIndex(NamespaceUri, LocalName) >= 0;
end;

function TLandrixXmlNode.AttributeValueUtf8(const NamespaceUri,
  LocalName: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I: Integer;
begin
  I := AttributeIndex(NamespaceUri, LocalName);
  if I >= 0 then
    Result := TLandrixXmlContainerNode(Self).FAttrs[I].Value
  else
    Result := '';
end;

function TLandrixXmlNode.AttributeValueW(const NamespaceUri,
  LocalName: TLandrixXmlUtf8): TLandrixXmlWide;
begin
  Result := LandrixXmlUtf8ToWide(AttributeValueUtf8(NamespaceUri, LocalName));
end;

function TLandrixXmlNode.AttributeValue(const NamespaceUri, LocalName: TLandrixXmlUtf8): string;
begin
  Result := LandrixXmlUtf8ToString(AttributeValueUtf8(NamespaceUri, LocalName));
end;

function TLandrixXmlNode.TryAttributeValueUtf8(const NamespaceUri, LocalName: TLandrixXmlUtf8;
  out Value: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  I := AttributeIndex(NamespaceUri, LocalName);
  Result := I >= 0;
  if Result then
    Value := TLandrixXmlContainerNode(Self).FAttrs[I].Value
  else
    Value := '';
end;

function TLandrixXmlNode.TryAttributeValueW(const NamespaceUri, LocalName: TLandrixXmlUtf8;
  out Value: TLandrixXmlWide): Boolean;
var
  V: TLandrixXmlUtf8;
begin
  Result := TryAttributeValueUtf8(NamespaceUri, LocalName, V);
  Value := LandrixXmlUtf8ToWide(V);
end;

function TLandrixXmlNode.TryAttributeValue(const NamespaceUri, LocalName: TLandrixXmlUtf8;
  out Value: string): Boolean;
var
  V: TLandrixXmlUtf8;
begin
  Result := TryAttributeValueUtf8(NamespaceUri, LocalName, V);
  Value := LandrixXmlUtf8ToString(V);
end;

procedure TLandrixXmlContainerNode.AddAttr(Name: TLandrixXmlName; const Value: TLandrixXmlUtf8);
begin
  if FAttrCount = Length(FAttrs) then
  begin
    if FAttrCount < 4 then
      SetLength(FAttrs, 4)
    else
      SetLength(FAttrs, 2 * FAttrCount);
  end;
  FAttrs[FAttrCount].Name := Name;
  FAttrs[FAttrCount].Value := Value;
  Inc(FAttrCount);
end;

{ Index of this element's own declaration of Prefix, -1 if none. }
function TLandrixXmlContainerNode.DeclaredPrefixIndex(const Prefix: TLandrixXmlUtf8): Integer;
var
  N: TLandrixXmlName;
begin
  for Result := 0 to FAttrCount - 1 do
  begin
    N := FAttrs[Result].Name;
    if N.FNamespaceUri <> LandrixXmlNamespaceXmlns then
      Continue;
    if Prefix = '' then
    begin
      if N.FPrefix = '' then
        Exit;
    end
    else if (N.FPrefix <> '') and (N.FLocalName = Prefix) then
      Exit;
  end;
  Result := -1;
end;

function TLandrixXmlNode.LookupNamespace(const Prefix: TLandrixXmlUtf8;
  out NamespaceUri: TLandrixXmlUtf8): Boolean;
var
  N: TLandrixXmlNode;
  I: Integer;
begin
  NamespaceUri := '';
  Result := True;
  if SameAscii(Prefix, 'xml') then
  begin
    NamespaceUri := LandrixXmlNamespaceXml;
    Exit;
  end;
  if SameAscii(Prefix, 'xmlns') then
  begin
    NamespaceUri := LandrixXmlNamespaceXmlns;
    Exit;
  end;
  N := Self;
  while N <> nil do
  begin
    if N.FNodeType = xntElement then
    begin
      I := TLandrixXmlContainerNode(N).DeclaredPrefixIndex(Prefix);
      if I >= 0 then
      begin
        NamespaceUri := TLandrixXmlContainerNode(N).FAttrs[I].Value;
        { xmlns="" undeclares the default namespace }
        Result := (Prefix <> '') or (NamespaceUri <> '');
        Exit;
      end;
    end;
    N := N.FParent;
  end;
  Result := False;
end;

procedure TLandrixXmlNode.DeclareNamespace(const Prefix, NamespaceUri: TLandrixXmlUtf8);
var
  I: Integer;
  Name: TLandrixXmlName;
  C: TLandrixXmlContainerNode;
begin
  CheckElement('DeclareNamespace');
  C := Cont(Self);
  if Prefix <> '' then
    CheckNcName(Prefix);
  CheckUtf8(NamespaceUri);
  if SameAscii(Prefix, 'xmlns') then
    RaiseNs('The prefix "xmlns" must not be declared');
  if SameAscii(Prefix, 'xml') then
  begin
    if NamespaceUri <> LandrixXmlNamespaceXml then
      RaiseNs('The prefix "xml" must not be bound to another namespace');
  end
  else
  begin
    if (NamespaceUri = LandrixXmlNamespaceXml) or (NamespaceUri = LandrixXmlNamespaceXmlns) then
      RaiseNs('Reserved namespace name must not be declared');
    if (Prefix <> '') and (NamespaceUri = '') then
      RaiseNs('A prefix must not be bound to an empty namespace name');
  end;
  I := C.DeclaredPrefixIndex(Prefix);
  if I >= 0 then
  begin
    if C.FAttrs[I].Value <> NamespaceUri then
      RaiseNs('The prefix is already declared with another namespace on this element');
    Exit;
  end;
  if Prefix <> '' then
  begin
    if (C.FName.FPrefix = Prefix) and (C.FName.FNamespaceUri <> NamespaceUri) then
      RaiseNs('The declaration would change the namespace of the element');
    for I := 0 to C.FAttrCount - 1 do
      if (C.FAttrs[I].Name.FPrefix = Prefix) and
        (C.FAttrs[I].Name.FNamespaceUri <> LandrixXmlNamespaceXmlns) and
        (C.FAttrs[I].Name.FNamespaceUri <> NamespaceUri) then
        RaiseNs('The declaration would change the namespace of an attribute');
  end;
  if Prefix = '' then
    Name := FDocument.FNames.Intern(nil, 0, 'xmlns', 5, LandrixXmlNamespaceXmlns,
      Length(LandrixXmlNamespaceXmlns))
  else
    Name := FDocument.FNames.Intern('xmlns', 5, PAnsiChar(Prefix), Length(Prefix),
      LandrixXmlNamespaceXmlns, Length(LandrixXmlNamespaceXmlns));
  C.AddAttr(Name, NamespaceUri);
end;

procedure TLandrixXmlNode.SetAttributeNsUtf8(const NamespaceUri, Prefix, LocalName,
  Value: TLandrixXmlUtf8);
var
  Uri: TLandrixXmlUtf8;
  I: Integer;
  Name: TLandrixXmlName;
  C: TLandrixXmlContainerNode;
begin
  CheckElement('SetAttribute');
  C := Cont(Self);
  CheckNcName(LocalName);
  CheckUtf8(Value);
  if NamespaceUri = '' then
  begin
    if Prefix <> '' then
      RaiseArg('A prefix needs a non-empty namespace name');
  end
  else
  begin
    if Prefix = '' then
      RaiseArg('A namespaced attribute needs a prefix');
    CheckNcName(Prefix);
    if SameAscii(Prefix, 'xmlns') or (NamespaceUri = LandrixXmlNamespaceXmlns) then
      RaiseNs('Use DeclareNamespace for namespace declarations');
    if not LookupNamespace(Prefix, Uri) or (Uri <> NamespaceUri) then
      DeclareNamespace(Prefix, NamespaceUri);
  end;
  Name := FDocument.FNames.Intern(PAnsiChar(Prefix), Length(Prefix), PAnsiChar(LocalName),
    Length(LocalName), PAnsiChar(NamespaceUri), Length(NamespaceUri));
  for I := 0 to C.FAttrCount - 1 do
    if C.FAttrs[I].Name.FExpandedId = Name.FExpandedId then
    begin
      C.FAttrs[I].Name := Name;
      C.FAttrs[I].Value := Value;
      Exit;
    end;
  C.AddAttr(Name, Value);
end;

procedure TLandrixXmlNode.SetAttributeUtf8(const QName, Value: TLandrixXmlUtf8);
var
  Colon: Integer;
  Prefix, Local, Uri: TLandrixXmlUtf8;
begin
  CheckElement('SetAttribute');
  Colon := CheckQName(QName);
  if SameAscii(QName, 'xmlns') then
  begin
    DeclareNamespace('', Value);
    Exit;
  end;
  if Colon < 0 then
  begin
    SetAttributeNsUtf8('', '', QName, Value);
    Exit;
  end;
  Prefix := SpanStr(PAnsiChar(QName), Colon);
  Local := SpanStr(PAnsiChar(QName) + Colon + 1, Length(QName) - Colon - 1);
  if SameAscii(Prefix, 'xmlns') then
  begin
    DeclareNamespace(Local, Value);
    Exit;
  end;
  if not LookupNamespace(Prefix, Uri) then
    RaiseNs('Undeclared namespace prefix "' + LandrixXmlEscapeForMessage(Prefix, 60) + '"');
  SetAttributeNsUtf8(Uri, Prefix, Local, Value);
end;

procedure TLandrixXmlNode.SetAttributeW(const QName: TLandrixXmlUtf8; const Value: TLandrixXmlWide);
begin
  SetAttributeUtf8(QName, LandrixXmlWideToUtf8(Value));
end;

procedure TLandrixXmlNode.SetAttribute(const QName: TLandrixXmlUtf8; const Value: string);
begin
  SetAttributeUtf8(QName, LandrixXmlStringToUtf8(Value));
end;

procedure TLandrixXmlNode.RemoveAttributeAt(Index: Integer);
var
  I: Integer;
  C: TLandrixXmlContainerNode;
begin
  CheckAttrIndex(Index);
  C := Cont(Self);
  for I := Index to C.FAttrCount - 2 do
    C.FAttrs[I] := C.FAttrs[I + 1];
  Dec(C.FAttrCount);
  C.FAttrs[C.FAttrCount].Name := nil;
  C.FAttrs[C.FAttrCount].Value := '';
end;

function TLandrixXmlNode.RemoveAttribute(const NamespaceUri, LocalName: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  I := AttributeIndex(NamespaceUri, LocalName);
  Result := I >= 0;
  if Result then
    RemoveAttributeAt(I);
end;

procedure TLandrixXmlNode.ClearAttributes;
var
  C: TLandrixXmlContainerNode;
begin
  C := AsContainer(Self);
  if C = nil then
    Exit;
  C.FAttrs := nil;
  C.FAttrCount := 0;
end;

{ --- searching ------------------------------------------------------------------ }

function TLandrixXmlNode.FindChild(const NamespaceUri, LocalName: TLandrixXmlUtf8): TLandrixXmlNode;
var
  Id, I: Integer;
  C: TLandrixXmlContainerNode;
  N: TLandrixXmlNode;
begin
  Result := nil;
  C := AsContainer(Self);
  if (C = nil) or (C.FChildCount = 0) or (FDocument = nil) then
    Exit;
  Id := FDocument.FNames.FindExpanded(PAnsiChar(NamespaceUri), Length(NamespaceUri),
    PAnsiChar(LocalName), Length(LocalName));
  if Id < 0 then
    Exit;
  for I := 0 to C.FChildCount - 1 do
  begin
    N := C.FChildren[I];
    if (N.FNodeType = xntElement) and
      (TLandrixXmlContainerNode(N).FName.FExpandedId = Id) then
    begin
      Result := N;
      Exit;
    end;
  end;
end;

function TLandrixXmlNode.FindChildLocal(const LocalName: TLandrixXmlUtf8): TLandrixXmlNode;
var
  I: Integer;
  C: TLandrixXmlContainerNode;
  N: TLandrixXmlNode;
begin
  Result := nil;
  C := AsContainer(Self);
  if C = nil then
    Exit;
  for I := 0 to C.FChildCount - 1 do
  begin
    N := C.FChildren[I];
    if (N.FNodeType = xntElement) and
      (TLandrixXmlContainerNode(N).FName.FLocalName = LocalName) then
    begin
      Result := N;
      Exit;
    end;
  end;
end;

function TLandrixXmlNode.FindChildren(const NamespaceUri, LocalName: TLandrixXmlUtf8;
  List: TList): Integer;
var
  Id, I: Integer;
  C: TLandrixXmlContainerNode;
  N: TLandrixXmlNode;
begin
  Result := 0;
  if List = nil then
    RaiseArg('List must not be nil');
  C := AsContainer(Self);
  if (C = nil) or (C.FChildCount = 0) or (FDocument = nil) then
    Exit;
  Id := FDocument.FNames.FindExpanded(PAnsiChar(NamespaceUri), Length(NamespaceUri),
    PAnsiChar(LocalName), Length(LocalName));
  if Id < 0 then
    Exit;
  for I := 0 to C.FChildCount - 1 do
  begin
    N := C.FChildren[I];
    if (N.FNodeType = xntElement) and
      (TLandrixXmlContainerNode(N).FName.FExpandedId = Id) then
    begin
      List.Add(N);
      Inc(Result);
    end;
  end;
end;

function TLandrixXmlNode.FindDescendant(const NamespaceUri, LocalName: TLandrixXmlUtf8): TLandrixXmlNode;
var
  Id, I: Integer;
  Stack: TList;
  C, E: TLandrixXmlContainerNode;
begin
  Result := nil;
  C := AsContainer(Self);
  if (C = nil) or (C.FChildCount = 0) or (FDocument = nil) then
    Exit;
  Id := FDocument.FNames.FindExpanded(PAnsiChar(NamespaceUri), Length(NamespaceUri),
    PAnsiChar(LocalName), Length(LocalName));
  if Id < 0 then
    Exit;
  Stack := TList.Create;
  try
    for I := C.FChildCount - 1 downto 0 do
      Stack.Add(C.FChildren[I]);
    while Stack.Count > 0 do
    begin
      { only elements are tested below; others are never dereferenced }
      E := TLandrixXmlContainerNode(Stack[Stack.Count - 1]);
      Stack.Delete(Stack.Count - 1);
      if E.FNodeType <> xntElement then
        Continue;
      if E.FName.FExpandedId = Id then
      begin
        Result := E;
        Exit;
      end;
      for I := E.FChildCount - 1 downto 0 do
        Stack.Add(E.FChildren[I]);
    end;
  finally
    Stack.Free;
  end;
end;

function TLandrixXmlNode.ChildTextUtf8(const NamespaceUri, LocalName: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  N: TLandrixXmlNode;
begin
  N := FindChild(NamespaceUri, LocalName);
  if N <> nil then
    Result := N.GetTextUtf8
  else
    Result := '';
end;

function TLandrixXmlNode.ChildTextW(const NamespaceUri, LocalName: TLandrixXmlUtf8): TLandrixXmlWide;
begin
  Result := LandrixXmlUtf8ToWide(ChildTextUtf8(NamespaceUri, LocalName));
end;

function TLandrixXmlNode.ChildText(const NamespaceUri, LocalName: TLandrixXmlUtf8): string;
begin
  Result := LandrixXmlUtf8ToString(ChildTextUtf8(NamespaceUri, LocalName));
end;

function TLandrixXmlNode.NodePathUtf8: TLandrixXmlUtf8;
var
  N, Sibling: TLandrixXmlNode;
  Step: TLandrixXmlUtf8;
  I, Same, Pos: Integer;
begin
  Result := '';
  N := Self;
  while (N <> nil) and (N.FNodeType <> xntDocument) do
  begin
    case N.FNodeType of
      xntElement:
        begin
          Step := TLandrixXmlContainerNode(N).FName.FQualifiedName;
          if N.FParent <> nil then
          begin
            Same := 0;
            Pos := 0;
            for I := 0 to N.FParent.FChildCount - 1 do
            begin
              Sibling := N.FParent.FChildren[I];
              if (Sibling.FNodeType = xntElement) and
                (TLandrixXmlContainerNode(Sibling).FName = TLandrixXmlContainerNode(N).FName) then
              begin
                Inc(Same);
                if Sibling = N then
                  Pos := Same;
              end;
            end;
            if Same > 1 then
              Step := Step + '[' + LandrixXmlStringToUtf8(IntToStr(Pos)) + ']';
          end;
        end;
      xntText:
        Step := 'text()';
      xntCData:
        Step := 'text()';
      xntComment:
        Step := 'comment()';
      xntProcessingInstruction:
        Step := 'processing-instruction()';
    else
      Step := 'doctype()';
    end;
    Result := '/' + Step + Result;
    N := N.FParent;
  end;
  if Result = '' then
    Result := '/';
end;

function TLandrixXmlNode.NodePath: string;
begin
  Result := LandrixXmlUtf8ToString(NodePathUtf8);
end;

{ --- building ---------------------------------------------------------------- }

function TLandrixXmlContainerNode.NewChild(NodeType: TLandrixXmlNodeType): TLandrixXmlNode;
begin
  Result := NewNodeOf(FDocument, NodeType);
  InsertAt(FChildCount, Result);
end;

function TLandrixXmlNode.AddElement(const NamespaceUri, Prefix,
  LocalName: TLandrixXmlUtf8): TLandrixXmlNode;
var
  Uri: TLandrixXmlUtf8;
  NeedDecl: Boolean;
begin
  CheckContainer('AddElement');
  CheckNcName(LocalName);
  if Prefix <> '' then
    CheckNcName(Prefix);
  CheckUtf8(NamespaceUri);
  if SameAscii(Prefix, 'xmlns') or (NamespaceUri = LandrixXmlNamespaceXmlns) then
    RaiseNs('Elements must not use the xmlns namespace');
  if SameAscii(Prefix, 'xml') <> (NamespaceUri = LandrixXmlNamespaceXml) then
    RaiseNs('The prefix "xml" and the XML namespace belong together');
  if (Prefix <> '') and (NamespaceUri = '') then
    RaiseArg('A prefix needs a non-empty namespace name');
  if (FNodeType = xntDocument) and (GetRoot_(Self) <> nil) then
    RaiseOp('The document already has a root element');
  if NamespaceUri = '' then
    { no namespace: undeclare an inherited default namespace }
    NeedDecl := (Prefix = '') and LookupNamespace('', Uri) and (Uri <> '')
  else
    NeedDecl := not SameAscii(Prefix, 'xml') and
      (not LookupNamespace(Prefix, Uri) or (Uri <> NamespaceUri));
  Result := Cont(Self).NewChild(xntElement);
  TLandrixXmlContainerNode(Result).FName := FDocument.FNames.Intern(PAnsiChar(Prefix),
    Length(Prefix), PAnsiChar(LocalName), Length(LocalName), PAnsiChar(NamespaceUri),
    Length(NamespaceUri));
  if NeedDecl then
    Result.DeclareNamespace(Prefix, NamespaceUri);
end;

function TLandrixXmlNode.AddElement(const QName: TLandrixXmlUtf8): TLandrixXmlNode;
var
  Colon: Integer;
  Prefix, Local, Uri: TLandrixXmlUtf8;
begin
  CheckContainer('AddElement');
  Colon := CheckQName(QName);
  if Colon < 0 then
  begin
    Prefix := '';
    Local := QName;
  end
  else
  begin
    Prefix := SpanStr(PAnsiChar(QName), Colon);
    Local := SpanStr(PAnsiChar(QName) + Colon + 1, Length(QName) - Colon - 1);
  end;
  if not LookupNamespace(Prefix, Uri) then
  begin
    if Prefix <> '' then
      RaiseNs('Undeclared namespace prefix "' + LandrixXmlEscapeForMessage(Prefix, 60) + '"');
    Uri := '';
  end;
  Result := AddElement(Uri, Prefix, Local);
end;

function TLandrixXmlNode.AddTextUtf8(const Value: TLandrixXmlUtf8): TLandrixXmlNode;
begin
  CheckElement('AddText');
  CheckUtf8(Value);
  Result := Cont(Self).NewChild(xntText);
  Result.FValue := Value;
end;

function TLandrixXmlNode.AddTextW(const Value: TLandrixXmlWide): TLandrixXmlNode;
begin
  Result := AddTextUtf8(LandrixXmlWideToUtf8(Value));
end;

function TLandrixXmlNode.AddText(const Value: string): TLandrixXmlNode;
begin
  Result := AddTextUtf8(LandrixXmlStringToUtf8(Value));
end;

function TLandrixXmlNode.AddCDataUtf8(const Value: TLandrixXmlUtf8): TLandrixXmlNode;
begin
  CheckElement('AddCData');
  CheckUtf8(Value);
  Result := Cont(Self).NewChild(xntCData);
  Result.FValue := Value;
end;

function TLandrixXmlNode.AddCDataW(const Value: TLandrixXmlWide): TLandrixXmlNode;
begin
  Result := AddCDataUtf8(LandrixXmlWideToUtf8(Value));
end;

function TLandrixXmlNode.AddCData(const Value: string): TLandrixXmlNode;
begin
  Result := AddCDataUtf8(LandrixXmlStringToUtf8(Value));
end;

function TLandrixXmlNode.AddCommentUtf8(const Value: TLandrixXmlUtf8): TLandrixXmlNode;
begin
  CheckContainer('AddComment');
  CheckUtf8(Value);
  Result := Cont(Self).NewChild(xntComment);
  Result.FValue := Value;
end;

function TLandrixXmlNode.AddCommentW(const Value: TLandrixXmlWide): TLandrixXmlNode;
begin
  Result := AddCommentUtf8(LandrixXmlWideToUtf8(Value));
end;

function TLandrixXmlNode.AddComment(const Value: string): TLandrixXmlNode;
begin
  Result := AddCommentUtf8(LandrixXmlStringToUtf8(Value));
end;

function TLandrixXmlNode.AddProcessingInstruction(const Target,
  Data: TLandrixXmlUtf8): TLandrixXmlNode;
begin
  CheckContainer('AddProcessingInstruction');
  CheckNcName(Target);
  CheckUtf8(Data);
  Result := Cont(Self).NewChild(xntProcessingInstruction);
  TLandrixXmlContainerNode(Result).FName := FDocument.FNames.Intern(nil, 0,
    PAnsiChar(Target), Length(Target), nil, 0);
  Result.FValue := Data;
end;

{ Adds declarations for prefixes used in this subtree that are not bound
  correctly at their place (after moving a subtree from a reader). }
procedure TLandrixXmlNode.EnsureDeclarations;
var
  Stack: TList;
  N: TLandrixXmlContainerNode;
  I: Integer;
  Uri: TLandrixXmlUtf8;

  procedure Need(Name: TLandrixXmlName; IsElementName: Boolean);
  var
    Found: Boolean;
  begin
    if (Name.FNamespaceUri = LandrixXmlNamespaceXmlns) or
      (Name.FNamespaceUri = LandrixXmlNamespaceXml) then
      Exit;
    if (Name.FPrefix = '') and not IsElementName then
      Exit;
    Found := N.LookupNamespace(Name.FPrefix, Uri);
    if Found and (Uri = Name.FNamespaceUri) then
      Exit;
    if not Found and (Name.FNamespaceUri = '') then
      Exit;
    DeclareNamespace(Name.FPrefix, Name.FNamespaceUri);
  end;

begin
  Stack := TList.Create;
  try
    Stack.Add(Self);
    while Stack.Count > 0 do
    begin
      { only elements are tested below; others are never dereferenced }
      N := TLandrixXmlContainerNode(Stack[Stack.Count - 1]);
      Stack.Delete(Stack.Count - 1);
      if N.FNodeType <> xntElement then
        Continue;
      Need(N.FName, True);
      for I := 0 to N.FAttrCount - 1 do
        Need(N.FAttrs[I].Name, False);
      for I := 0 to N.FChildCount - 1 do
        Stack.Add(N.FChildren[I]);
    end;
  finally
    Stack.Free;
  end;
end;

function TLandrixXmlNode.AppendFromReader(Reader: TLandrixXmlReader): TLandrixXmlNode;
begin
  CheckContainer('AppendFromReader');
  if (Reader = nil) or (Reader.TokenType <> xttStartElement) then
    RaiseArg('The reader must be positioned on a start tag');
  if (FNodeType = xntDocument) and (GetRoot_(Self) <> nil) then
    RaiseOp('The document already has a root element');
  Result := FDocument.Build(Reader, Self, True);
  Result.EnsureDeclarations;
end;

{ --- writing ------------------------------------------------------------------- }

function HasTextChild(N: TLandrixXmlContainerNode): Boolean;
var
  I: Integer;
begin
  for I := 0 to N.FChildCount - 1 do
    if N.FChildren[I].FNodeType in [xntText, xntCData] then
    begin
      Result := True;
      Exit;
    end;
  Result := False;
end;

procedure WriteStart(N: TLandrixXmlContainerNode; Writer: TLandrixXmlWriter; Outer: Boolean);
var
  I, J: Integer;
  A: TLandrixXmlContainerNode;
  Seen: TList;
  Name: TLandrixXmlName;
begin
  Writer.StartElement(N.FName.FQualifiedName, HasTextChild(N));
  for I := 0 to N.FAttrCount - 1 do
    Writer.AttributeUtf8(N.FAttrs[I].Name.FQualifiedName, N.FAttrs[I].Value);
  if not Outer or (N.FParent = nil) or (N.FParent.FNodeType <> xntElement) then
    Exit;
  { a subtree written on its own repeats the declarations in scope }
  Seen := TList.Create;
  try
    { declaration names are interned: the same prefix is the same object }
    for I := 0 to N.FAttrCount - 1 do
      if N.FAttrs[I].Name.FNamespaceUri = LandrixXmlNamespaceXmlns then
        Seen.Add(N.FAttrs[I].Name);
    A := N.FParent;
    while (A <> nil) and (A.FNodeType = xntElement) do
    begin
      for J := 0 to A.FAttrCount - 1 do
      begin
        Name := A.FAttrs[J].Name;
        if Name.FNamespaceUri <> LandrixXmlNamespaceXmlns then
          Continue;
        if Seen.IndexOf(Name) >= 0 then
          Continue;
        Seen.Add(Name);
        Writer.AttributeUtf8(Name.FQualifiedName, A.FAttrs[J].Value);
      end;
      A := A.FParent;
    end;
  finally
    Seen.Free;
  end;
end;

procedure TLandrixXmlNode.WriteTo(Writer: TLandrixXmlWriter);
var
  Nodes: array of TLandrixXmlContainerNode;
  NextChild: array of Integer;
  Top: Integer;
  N: TLandrixXmlContainerNode;
  C: TLandrixXmlNode;
  I: Integer;
begin
  if Writer = nil then
    RaiseArg('Writer must not be nil');
  case FNodeType of
    xntDocument:
      begin
        N := TLandrixXmlContainerNode(Self);
        for I := 0 to N.FChildCount - 1 do
          N.FChildren[I].WriteTo(Writer);
        Exit;
      end;
    xntText:
      begin
        Writer.TextUtf8(FValue);
        Exit;
      end;
    xntCData:
      begin
        Writer.CDataUtf8(FValue);
        Exit;
      end;
    xntComment:
      begin
        Writer.CommentUtf8(FValue);
        Exit;
      end;
    xntProcessingInstruction:
      begin
        Writer.ProcessingInstructionUtf8(TLandrixXmlContainerNode(Self).FName.FQualifiedName,
          FValue);
        Exit;
      end;
    xntDocumentType:
      begin
        Writer.DocumentType(TLandrixXmlContainerNode(Self).FName.FQualifiedName, FValue);
        Exit;
      end;
  else
    ;
  end;
  Nodes := nil;
  NextChild := nil;
  SetLength(Nodes, 16);
  SetLength(NextChild, 16);
  N := TLandrixXmlContainerNode(Self);
  WriteStart(N, Writer, True);
  Top := 0;
  Nodes[0] := N;
  NextChild[0] := 0;
  while Top >= 0 do
  begin
    N := Nodes[Top];
    if NextChild[Top] >= N.FChildCount then
    begin
      Writer.EndElement;
      Dec(Top);
      Continue;
    end;
    C := N.FChildren[NextChild[Top]];
    Inc(NextChild[Top]);
    if C.FNodeType = xntElement then
    begin
      WriteStart(TLandrixXmlContainerNode(C), Writer, False);
      Inc(Top);
      if Top = Length(Nodes) then
      begin
        SetLength(Nodes, 2 * Top);
        SetLength(NextChild, 2 * Top);
      end;
      Nodes[Top] := TLandrixXmlContainerNode(C);
      NextChild[Top] := 0;
    end
    else
      C.WriteTo(Writer);
  end;
end;

{ --- TLandrixXmlDocument ---------------------------------------------------------- }

constructor TLandrixXmlDocument.Create;
begin
  inherited CreateNode(nil, xntDocument);
  FDocument := Self;
  FNames := TLandrixXmlNameTable.Create;
  FDetachedNodes := TList.Create;
  FKeepComments := True;
  FKeepProcessingInstructions := True;
  FMaxDepth := LandrixXmlDefaultMaxDepth;
  FWriteDeclaration := True;
  FLineBreak := xlbLF;
end;

destructor TLandrixXmlDocument.Destroy;
begin
  Clear;
  FDetachedNodes.Free;
  FDetachedNodes := nil;
  inherited Destroy;
  FNames.Free;
end;

procedure TLandrixXmlDocument.Clear;
var
  N: TLandrixXmlNode;
begin
  FreeChildren;
  while (FDetachedNodes <> nil) and (FDetachedNodes.Count > 0) do
  begin
    N := TLandrixXmlNode(FDetachedNodes[FDetachedNodes.Count - 1]);
    FDetachedNodes.Delete(FDetachedNodes.Count - 1);
    N.FIndex := -1;
    N.Free;
  end;
  FVersion := '';
  FStandalone := '';
  FSourceEncoding := xenUnknown;
  FDeclaredEncoding := '';
  FHadBom := False;
end;

function TLandrixXmlDocument.GetRoot: TLandrixXmlNode;
begin
  Result := GetRoot_(Self);
end;

procedure TLandrixXmlDocument.SetStandalone(const Value: TLandrixXmlUtf8);
begin
  if (Value <> '') and not SameAscii(Value, 'yes') and not SameAscii(Value, 'no') then
    RaiseArg('Standalone must be '''', ''yes'' or ''no''');
  FStandalone := Value;
end;

procedure TLandrixXmlDocument.SetMaxDepth(Value: Integer);
begin
  if Value < 1 then
    RaiseArg('MaxDepth must be at least 1');
  FMaxDepth := Value;
end;

type
  TBuildLevel = record
    Node: TLandrixXmlContainerNode;
    Start: Integer;
    Preserve: Boolean;
    HasText: Boolean;
  end;

{ Builds nodes from the reader. Subtree: the reader is on a start tag; that
  element is built and returned. Otherwise the whole document is read into
  Target (the document). }
function TLandrixXmlDocument.Build(Reader: TLandrixXmlReader; Target: TLandrixXmlNode;
  Subtree: Boolean): TLandrixXmlNode;
var
  Pending: array of TLandrixXmlNode;
  PendingCount: Integer;
  Levels: array of TBuildLevel;
  LevelCount: Integer;
  N: TLandrixXmlNode;
  E, T: TLandrixXmlContainerNode;
  I, J, K, Count: Integer;
  Drop: Boolean;
  Done: Boolean;
  { white-space-only text values are shared: indented documents repeat the
    same few strings millions of times }
  WsCache: array[0..63] of TLandrixXmlUtf8;

  procedure Push(Node: TLandrixXmlNode);
  begin
    if PendingCount = Length(Pending) then
      SetLength(Pending, 2 * PendingCount + 16);
    Pending[PendingCount] := Node;
    Inc(PendingCount);
  end;

  function NewNode(NodeType: TLandrixXmlNodeType): TLandrixXmlNode;
  begin
    Result := NewNodeOf(Self, NodeType);
    Result.FLine := Reader.Line;
    Result.FColumn := Reader.Column;
    Push(Result);
  end;

  function SharedWhitespace(const Span: TLandrixXmlSpan): TLandrixXmlUtf8;
  var
    Slot: Integer;
  begin
    Slot := Integer(LandrixXmlHashBytes(Span.P, Span.Len, LandrixXmlHashSeed) and 63);
    if not SameBuf(Span.P, Span.Len, WsCache[Slot]) then
      WsCache[Slot] := SpanStr(Span.P, Span.Len);
    Result := WsCache[Slot];
  end;

  procedure StartElement;
  var
    E: TLandrixXmlContainerNode;
    A: Integer;
    S1, S2, S3: TLandrixXmlSpan;
    Preserve: Boolean;
  begin
    E := TLandrixXmlContainerNode(NewNode(xntElement));
    S1 := Reader.PrefixSpan;
    S2 := Reader.LocalNameSpan;
    S3 := Reader.NamespaceUriSpan;
    E.FName := FNames.Intern(S1.P, S1.Len, S2.P, S2.Len, S3.P, S3.Len);
    E.FIsEmpty := Reader.IsEmptyElement;
    if Reader.AttributeCount > 0 then
    begin
      SetLength(E.FAttrs, Reader.AttributeCount);
      for A := 0 to Reader.AttributeCount - 1 do
      begin
        S1 := Reader.AttributePrefixSpan(A);
        S2 := Reader.AttributeLocalNameSpan(A);
        S3 := Reader.AttributeNamespaceUriSpan(A);
        E.FAttrs[A].Name := FNames.Intern(S1.P, S1.Len, S2.P, S2.Len, S3.P, S3.Len);
        E.FAttrs[A].Value := Reader.AttributeValueUtf8(A);
      end;
      E.FAttrCount := Reader.AttributeCount;
    end;
    if LevelCount > 0 then
      Preserve := Levels[LevelCount - 1].Preserve
    else
      Preserve := False;
    for A := 0 to E.FAttrCount - 1 do
      if (E.FAttrs[A].Name.FNamespaceUri = LandrixXmlNamespaceXml) and
        SameAscii(E.FAttrs[A].Name.FLocalName, 'space') then
      begin
        if SameAscii(E.FAttrs[A].Value, 'preserve') then
          Preserve := True
        else if SameAscii(E.FAttrs[A].Value, 'default') then
          Preserve := False;
      end;
    if LevelCount = Length(Levels) then
      SetLength(Levels, 2 * LevelCount + 16);
    Levels[LevelCount].Node := E;
    Levels[LevelCount].Start := PendingCount;
    Levels[LevelCount].Preserve := Preserve;
    Levels[LevelCount].HasText := False;
    Inc(LevelCount);
  end;

begin
  Result := nil;
  PendingCount := 0;
  LevelCount := 0;
  Done := False;
  try
    if Subtree then
      StartElement;
    while not Done and Reader.Read do
    begin
      case Reader.TokenType of
        xttStartElement:
          StartElement;
        xttEndElement:
          begin
            Dec(LevelCount);
            E := Levels[LevelCount].Node;
            Count := PendingCount - Levels[LevelCount].Start;
            Drop := (FWhitespaceMode = xwmDropBetweenElements) and
              not Levels[LevelCount].Preserve and not Levels[LevelCount].HasText;
            if Count > 0 then
            begin
              SetLength(E.FChildren, Count);
              K := 0;
              for I := Levels[LevelCount].Start to PendingCount - 1 do
              begin
                if Drop and Pending[I].FIsWhitespace then
                begin
                  Pending[I].Free;
                  Pending[I] := nil;
                  Continue;
                end;
                E.FChildren[K] := Pending[I];
                Pending[I].FParent := E;
                Pending[I].FIndex := K;
                Inc(K);
                E.FChildCount := K;
              end;
              if K < Count then
                SetLength(E.FChildren, K);
            end;
            PendingCount := Levels[LevelCount].Start;
            if Subtree and (LevelCount = 0) then
              Done := True;
          end;
        xttText, xttCData:
          begin
            if Reader.TokenType = xttText then
              N := NewNode(xntText)
            else
              N := NewNode(xntCData);
            if (Reader.TokenType = xttText) and Reader.IsWhitespace and
              (Reader.ValueSpan.Len <= 256) then
              N.FValue := SharedWhitespace(Reader.ValueSpan)
            else
              N.FValue := Reader.ValueUtf8;
            N.FIsWhitespace := (Reader.TokenType = xttText) and Reader.IsWhitespace;
            if not N.FIsWhitespace and (LevelCount > 0) then
              Levels[LevelCount - 1].HasText := True;
          end;
        xttComment:
          if FKeepComments then
            NewNode(xntComment).FValue := Reader.ValueUtf8;
        xttProcessingInstruction:
          if FKeepProcessingInstructions then
          begin
            E := TLandrixXmlContainerNode(NewNode(xntProcessingInstruction));
            E.FName := FNames.Intern(nil, 0, Reader.NameSpan.P, Reader.NameSpan.Len, nil, 0);
            E.FValue := Reader.ValueUtf8;
          end;
        xttDocumentType:
          begin
            E := TLandrixXmlContainerNode(NewNode(xntDocumentType));
            E.FName := FNames.Intern(nil, 0, Reader.NameSpan.P, Reader.NameSpan.Len, nil, 0);
            E.FValue := Reader.ValueUtf8;
          end;
      else
        ;
      end;
    end;
    { attach the top-level nodes }
    T := Cont(Target);
    if Subtree then
    begin
      Result := Pending[0];
      T.InsertAt(T.FChildCount, Result);
    end
    else
      for J := 0 to PendingCount - 1 do
        T.InsertAt(T.FChildCount, Pending[J]);
    PendingCount := 0;
  except
    for J := PendingCount - 1 downto 0 do
      if (Pending[J] <> nil) and (Pending[J].FParent = nil) then
        Pending[J].Free;
    raise;
  end;
end;

procedure TLandrixXmlDocument.PrepareReader(Reader: TLandrixXmlReader);
begin
  Reader.MaxDepth := FMaxDepth;
  Reader.Input.FallbackEncoding := FFallbackEncoding;
  Reader.Input.Latin1AsWindows1252 := FLatin1AsWindows1252;
end;

procedure TLandrixXmlDocument.LoadWith(Reader: TLandrixXmlReader);
begin
  try
    Build(Reader, Self, False);
  except
    Clear;
    raise;
  end;
  FVersion := Reader.Version;
  FStandalone := Reader.Standalone;
  FSourceEncoding := Reader.Input.SourceEncoding;
  FDeclaredEncoding := Reader.Input.DeclaredEncoding;
  FHadBom := Reader.Input.HadBom;
end;

procedure TLandrixXmlDocument.LoadFromFile(const FileName: string);
var
  Reader: TLandrixXmlReader;
begin
  Clear;
  Reader := TLandrixXmlReader.Create;
  try
    PrepareReader(Reader);
    Reader.LoadFromFile(FileName);
    LoadWith(Reader);
  finally
    Reader.Free;
  end;
end;

procedure TLandrixXmlDocument.LoadFromStream(Stream: TStream);
var
  Reader: TLandrixXmlReader;
begin
  Clear;
  Reader := TLandrixXmlReader.Create;
  try
    PrepareReader(Reader);
    Reader.LoadFromStream(Stream);
    LoadWith(Reader);
  finally
    Reader.Free;
  end;
end;

procedure TLandrixXmlDocument.LoadFromBuffer(const Data; Size: Integer);
var
  Reader: TLandrixXmlReader;
  Src: PAnsiChar;
begin
  Clear;
  Reader := TLandrixXmlReader.Create;
  try
    PrepareReader(Reader);
    Src := PAnsiChar(@Data);
    Reader.LoadFromBuffer(Src^, Size);
    LoadWith(Reader);
  finally
    Reader.Free;
  end;
end;

procedure TLandrixXmlDocument.LoadFromUtf8(const S: TLandrixXmlUtf8);
var
  Reader: TLandrixXmlReader;
begin
  Clear;
  Reader := TLandrixXmlReader.Create;
  try
    PrepareReader(Reader);
    Reader.LoadFromUtf8(S);
    LoadWith(Reader);
  finally
    Reader.Free;
  end;
end;

procedure TLandrixXmlDocument.LoadFromString(const S: string);
var
  Reader: TLandrixXmlReader;
begin
  Clear;
  Reader := TLandrixXmlReader.Create;
  try
    PrepareReader(Reader);
    Reader.LoadFromString(S);
    LoadWith(Reader);
  finally
    Reader.Free;
  end;
end;

procedure TLandrixXmlDocument.ConfigureWriter(Writer: TLandrixXmlWriter);
begin
  Writer.Indent := FIndent;
  Writer.LineBreak := FLineBreak;
  Writer.WriteBom := FWriteBom;
  Writer.WriteDeclaration := FWriteDeclaration;
  if SameAscii(FStandalone, 'yes') then
    Writer.Standalone := xsaYes
  else if SameAscii(FStandalone, 'no') then
    Writer.Standalone := xsaNo;
end;

procedure TLandrixXmlDocument.SaveToWriter(Writer: TLandrixXmlWriter);
begin
  WriteTo(Writer);
end;

procedure TLandrixXmlDocument.SaveToStream(Stream: TStream);
var
  Writer: TLandrixXmlWriter;
begin
  Writer := TLandrixXmlWriter.Create(Stream);
  try
    ConfigureWriter(Writer);
    SaveToWriter(Writer);
    Writer.EndDocument;
  finally
    Writer.Free;
  end;
end;

procedure TLandrixXmlDocument.SaveToFile(const FileName: string);
var
  Writer: TLandrixXmlWriter;
begin
  { written to memory first, so an invalid document never leaves a half
    file behind (costs the size of the output in memory) }
  Writer := TLandrixXmlWriter.Create;
  try
    ConfigureWriter(Writer);
    SaveToWriter(Writer);
    Writer.EndDocument;
    Writer.SaveToFile(FileName);
  finally
    Writer.Free;
  end;
end;

function TLandrixXmlDocument.SaveToUtf8: TLandrixXmlUtf8;
var
  Writer: TLandrixXmlWriter;
begin
  Writer := TLandrixXmlWriter.Create;
  try
    ConfigureWriter(Writer);
    SaveToWriter(Writer);
    Writer.EndDocument;
    Result := Writer.AsUtf8;
  finally
    Writer.Free;
  end;
end;

function TLandrixXmlDocument.SaveToString: string;
begin
  Result := LandrixXmlUtf8ToString(SaveToUtf8);
end;

end.
