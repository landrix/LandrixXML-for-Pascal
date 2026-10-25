{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  A read-only tree of a document for XPath: the nodes of the XPath data
  model in flat arrays, numbered in document order. It is built once,
  from the pull reader or from a loaded DOM, and does not change; a DOM
  changed afterwards needs a new tree. Every accessor but LocationPathUtf8
  only reads, so threads may share a tree they do not ask for location
  paths (LocationPathUtf8 computes sibling positions when first needed).

  Node 0 is the document node. An element is followed by its attributes,
  then its children, as XPath orders them; SubtreeEnd is the last node
  below it, so every axis is a loop over index ranges. Namespace
  declarations are not attributes (the tree keeps them for
  LookupNamespace and InScopePrefixesUtf8); adjacent text and CDATA form one text
  node; white space is kept (as Saxon keeps it); comments and processing
  instructions are nodes; text outside the root element and the document
  type are not. Names are numbered: nodes with the same namespace URI and
  local name have the same ExpandedName, so a name test compares
  integers.

  Built from a DOM, every node keeps its DOM node (an attribute the
  element and the attribute index, a merged text node the first part);
  the tree then shows what the DOM holds (comments only if it kept them,
  white space as its WhitespaceMode left it): a tree as Saxon builds it
  needs a DOM loaded with the defaults (comments and processing
  instructions kept, xwmPreserve).

  The strings are UTF-8 (the accessors end in Utf8, as in the reader and
  the DOM). After a load that fails the tree is empty (only the document
  node). }

unit LandrixXmlXPathTree;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  Classes,
  LandrixXmlBase,
  LandrixXmlReader,
  LandrixXmlDom;

type
  TLandrixXmlXPathNodeKind = (xnkDocument, xnkElement, xnkAttribute, xnkText, xnkComment,
    xnkProcessingInstruction);

  { Internal, public only because Delphi 6 has no nested types. }
  TLandrixXmlXPathIntArray = array of Integer;
  TLandrixXmlXPathKindArray = array of TLandrixXmlXPathNodeKind;
  TLandrixXmlXPathDomArray = array of TLandrixXmlNode;

  TLandrixXmlXPathTree = class
  private
    FCount: Integer;
    FKinds: TLandrixXmlXPathKindArray;
    FParents: TLandrixXmlXPathIntArray;
    FNexts: TLandrixXmlXPathIntArray;
    FEnds: TLandrixXmlXPathIntArray;
    FAttrCounts: TLandrixXmlXPathIntArray;
    FNameIds: TLandrixXmlXPathIntArray;
    FValues: TLandrixXmlUtf8Array;
    FLines: TLandrixXmlXPathIntArray;
    FColumns: TLandrixXmlXPathIntArray;
    FDomNodes: TLandrixXmlXPathDomArray;
    FDomAttrs: TLandrixXmlXPathIntArray;
    { the first namespace declaration of an element, -1 if none; the
      declarations of an element are consecutive (FDeclOwners) }
    FDeclFirsts: TLandrixXmlXPathIntArray;
    FDeclCount: Integer;
    FDeclOwners: TLandrixXmlXPathIntArray;
    FDeclPrefixes: TLandrixXmlUtf8Array;
    FDeclUris: TLandrixXmlUtf8Array;
    { the position among the siblings of the same kind and name, computed
      for all children of a parent when first needed; 0 = not yet }
    FPositions: TLandrixXmlXPathIntArray;
    { names: local name, namespace URI and prefix per name id; the
      expanded name id shared by names that differ only in the prefix }
    FNameCount: Integer;
    FNameLocals: TLandrixXmlUtf8Array;
    FNameUris: TLandrixXmlUtf8Array;
    FNamePrefixes: TLandrixXmlUtf8Array;
    FNameExpanded: TLandrixXmlXPathIntArray;
    FExpandedCount: Integer;
    FNameKeys: TLandrixXmlUtf8Array;
    FNameSlots: TLandrixXmlXPathIntArray;
    FExpandedKeys: TLandrixXmlUtf8Array;
    FExpandedSlots: TLandrixXmlXPathIntArray;
    { building }
    FStack: TLandrixXmlXPathIntArray;
    FLastChild: TLandrixXmlXPathIntArray;
    FDepth: Integer;
    procedure Clear;
    function NameId(const NamespaceUri, Prefix, LocalName: TLandrixXmlUtf8): Integer;
    function LookupExpanded(const Key: TLandrixXmlUtf8; Add: Boolean): Integer;
    function NewNode(Kind: TLandrixXmlXPathNodeKind; Line, Column: Integer): Integer;
    procedure AddChild(Kind: TLandrixXmlXPathNodeKind; Line, Column: Integer; out Index: Integer);
    procedure AddText(const Value: TLandrixXmlUtf8; Line, Column: Integer; DomNode: TLandrixXmlNode);
    procedure StartElement(const NamespaceUri, Prefix, LocalName: TLandrixXmlUtf8; Line, Column: Integer;
      DomNode: TLandrixXmlNode);
    procedure AddAttribute(const NamespaceUri, Prefix, LocalName, Value: TLandrixXmlUtf8;
      DomNode: TLandrixXmlNode; DomIndex: Integer);
    procedure AddDeclaration(const Prefix, NamespaceUri: TLandrixXmlUtf8);
    procedure EndElement;
    procedure Finish;
    function DeclarationIndex(Element: Integer; const Prefix: TLandrixXmlUtf8): Integer;
    function NamedPrefixUri(Element: Integer; const Prefix: TLandrixXmlUtf8;
      out NamespaceUri: TLandrixXmlUtf8): Boolean;
    function ElementOf(Index: Integer): Integer;
    procedure ComputePositions(Parent: Integer);
    function GetKind(Index: Integer): TLandrixXmlXPathNodeKind;
    function GetParent(Index: Integer): Integer;
    function GetNextSibling(Index: Integer): Integer;
    function GetSubtreeEnd(Index: Integer): Integer;
    function GetAttributeCount(Index: Integer): Integer;
    function GetExpandedName(Index: Integer): Integer;
    function GetLine(Index: Integer): Integer;
    function GetColumn(Index: Integer): Integer;
    function GetDomNode(Index: Integer): TLandrixXmlNode;
    function GetDomAttributeIndex(Index: Integer): Integer;
  public
    constructor Create;
    { Reads the document (positions: start of each node; an attribute has
      the position of its element). Malformed XML raises ELandrixXmlError
      and leaves the tree empty. }
    procedure LoadFromReader(Reader: TLandrixXmlReader);
    procedure LoadFromFile(const FileName: string);
    procedure LoadFromUtf8(const S: TLandrixXmlUtf8);
    { The tree of a loaded document, with its DOM nodes (see the unit
      header for the DOM options that change it). }
    procedure LoadFromDocument(Document: TLandrixXmlDocument);
    { the number of nodes, at least 1 (the document node) }
    property Count: Integer read FCount;
    property Kind[Index: Integer]: TLandrixXmlXPathNodeKind read GetKind;
    { -1 for the document node }
    property Parent[Index: Integer]: Integer read GetParent;
    { the next child of the same parent; -1 if none and for attributes }
    property NextSibling[Index: Integer]: Integer read GetNextSibling;
    { the last node of the subtree (attributes included), Index if none }
    property SubtreeEnd[Index: Integer]: Integer read GetSubtreeEnd;
    property AttributeCount[Index: Integer]: Integer read GetAttributeCount;
    { the first child that is not an attribute; -1 if none }
    function FirstChild(Index: Integer): Integer;
    { the root element; -1 for an empty tree }
    function DocumentElement: Integer;
    { an integer for namespace URI plus local name, -1 for unnamed nodes;
      the name of a processing instruction is its target }
    property ExpandedName[Index: Integer]: Integer read GetExpandedName;
    { the id of the expanded name, -1 if no node of the tree has it }
    function FindExpandedName(const NamespaceUri, LocalName: TLandrixXmlUtf8): Integer;
    function LocalNameUtf8(Index: Integer): TLandrixXmlUtf8;
    function NamespaceUriUtf8(Index: Integer): TLandrixXmlUtf8;
    function PrefixUtf8(Index: Integer): TLandrixXmlUtf8;
    { the name as written in the document (prefix:local) }
    function NameUtf8(Index: Integer): TLandrixXmlUtf8;
    { the value of an attribute, text, comment or processing instruction;
      '' for elements and the document }
    function ValueUtf8(Index: Integer): TLandrixXmlUtf8;
    { XPath's string value: for elements and the document the text of
      all descendant text nodes }
    function StringValueUtf8(Index: Integer): TLandrixXmlUtf8;
    { The location as SchXslt writes it: per step Q, the namespace URI in
      curly brackets, the local name and [n] for an element, the same with
      a leading @ and no [n] for an attribute, text()[n], comment()[n] and
      processing-instruction("name")[n]; n counts the preceding siblings
      of the same kind (and name), starting at 1. }
    function LocationPathUtf8(Index: Integer): TLandrixXmlUtf8;
    property Line[Index: Integer]: Integer read GetLine;
    property Column[Index: Integer]: Integer read GetColumn;
    { nil when the tree was read from a reader }
    property DomNode[Index: Integer]: TLandrixXmlNode read GetDomNode;
    { the attribute's index in DomNode, -1 for other nodes }
    property DomAttributeIndex[Index: Integer]: Integer read GetDomAttributeIndex;
    { The namespace bound to Prefix ('' = default namespace) in the scope
      of an element (an attribute: of its element): the nearest
      declaration; "xml" is always bound, "xmlns" never (unlike the
      reader and the DOM); xmlns="" undeclares the default namespace.
      Without a declaration the prefix of the name of the element or of
      one of its attributes counts, here or at an ancestor (a DOM may
      have lost an xmlns attribute; a name in no namespace does not
      undeclare the default namespace). False for other nodes and an
      unbound prefix (NamespaceUri ''). }
    function LookupNamespace(Index: Integer; const Prefix: TLandrixXmlUtf8;
      out NamespaceUri: TLandrixXmlUtf8): Boolean;
    { The prefixes LookupNamespace binds for this node, each once, '' for
      a default namespace, "xml" included; the order is stable but not
      part of the contract. Empty for nodes that are no element or
      attribute. }
    function InScopePrefixesUtf8(Index: Integer): TLandrixXmlUtf8Array;
  end;

implementation

{ --- name tables: open addressing over string keys ---------------------- }

function KeyHash(const Key: TLandrixXmlUtf8): Cardinal;
begin
  if Key = '' then
    Result := LandrixXmlHashSeed
  else
    Result := LandrixXmlHashBytes(PAnsiChar(Key), Length(Key), LandrixXmlHashSeed);
end;

{ Finds Key in Keys/Slots (slot value = id + 1, 0 = free); returns the
  slot index. }
function FindSlot(const Keys: TLandrixXmlUtf8Array; const Slots: TLandrixXmlXPathIntArray;
  const Key: TLandrixXmlUtf8): Integer;
var
  Mask: Integer;
begin
  Mask := Integer(Length(Slots)) - 1;
  Result := Integer(KeyHash(Key) and Cardinal(Mask));
  while (Slots[Result] <> 0) and (Keys[Slots[Result] - 1] <> Key) do
    Result := (Result + 1) and Mask;
end;

procedure Rehash(var Keys: TLandrixXmlUtf8Array; var Slots: TLandrixXmlXPathIntArray; Count: Integer);
var
  I, S: Integer;
begin
  SetLength(Slots, 2 * Length(Slots));
  for I := 0 to Integer(Length(Slots)) - 1 do
    Slots[I] := 0;
  for I := 0 to Count - 1 do
  begin
    S := FindSlot(Keys, Slots, Keys[I]);
    Slots[S] := I + 1;
  end;
end;

{ --- TLandrixXmlXPathTree ---------------------------------------------- }

constructor TLandrixXmlXPathTree.Create;
begin
  inherited Create;
  Clear;
end;

procedure TLandrixXmlXPathTree.Clear;
var
  I: Integer;
begin
  FCount := 0;
  FKinds := nil;
  FParents := nil;
  FNexts := nil;
  FEnds := nil;
  FAttrCounts := nil;
  FNameIds := nil;
  FValues := nil;
  FLines := nil;
  FColumns := nil;
  FDomNodes := nil;
  FDomAttrs := nil;
  FDeclFirsts := nil;
  FDeclCount := 0;
  FDeclOwners := nil;
  FDeclPrefixes := nil;
  FDeclUris := nil;
  FNameCount := 0;
  FNameLocals := nil;
  FNameUris := nil;
  FNamePrefixes := nil;
  FNameExpanded := nil;
  FExpandedCount := 0;
  FNameKeys := nil;
  FExpandedKeys := nil;
  SetLength(FNameSlots, 64);
  SetLength(FExpandedSlots, 64);
  for I := 0 to 63 do
  begin
    FNameSlots[I] := 0;
    FExpandedSlots[I] := 0;
  end;
  FStack := nil;
  FLastChild := nil;
  FDepth := 0;
  FPositions := nil;
  NewNode(xnkDocument, 1, 1);
end;

function TLandrixXmlXPathTree.LookupExpanded(const Key: TLandrixXmlUtf8; Add: Boolean): Integer;
var
  S: Integer;
begin
  S := FindSlot(FExpandedKeys, FExpandedSlots, Key);
  if FExpandedSlots[S] <> 0 then
  begin
    Result := FExpandedSlots[S] - 1;
    Exit;
  end;
  if not Add then
  begin
    Result := -1;
    Exit;
  end;
  if FExpandedCount = Length(FExpandedKeys) then
    SetLength(FExpandedKeys, 2 * FExpandedCount + 16);
  FExpandedKeys[FExpandedCount] := Key;
  Result := FExpandedCount;
  Inc(FExpandedCount);
  FExpandedSlots[S] := FExpandedCount;
  if 2 * FExpandedCount > Length(FExpandedSlots) then
    Rehash(FExpandedKeys, FExpandedSlots, FExpandedCount);
end;

function TLandrixXmlXPathTree.NameId(const NamespaceUri, Prefix, LocalName: TLandrixXmlUtf8): Integer;
var
  Key: TLandrixXmlUtf8;
  S: Integer;
begin
  Key := NamespaceUri + #0 + Prefix + #0 + LocalName;
  S := FindSlot(FNameKeys, FNameSlots, Key);
  if FNameSlots[S] <> 0 then
  begin
    Result := FNameSlots[S] - 1;
    Exit;
  end;
  if FNameCount = Length(FNameKeys) then
  begin
    SetLength(FNameKeys, 2 * FNameCount + 16);
    SetLength(FNameLocals, 2 * FNameCount + 16);
    SetLength(FNameUris, 2 * FNameCount + 16);
    SetLength(FNamePrefixes, 2 * FNameCount + 16);
    SetLength(FNameExpanded, 2 * FNameCount + 16);
  end;
  Result := FNameCount;
  FNameKeys[Result] := Key;
  FNameLocals[Result] := LocalName;
  FNameUris[Result] := NamespaceUri;
  FNamePrefixes[Result] := Prefix;
  FNameExpanded[Result] := LookupExpanded(NamespaceUri + #0 + LocalName, True);
  Inc(FNameCount);
  FNameSlots[S] := FNameCount;
  if 2 * FNameCount > Length(FNameSlots) then
    Rehash(FNameKeys, FNameSlots, FNameCount);
end;

function TLandrixXmlXPathTree.NewNode(Kind: TLandrixXmlXPathNodeKind; Line, Column: Integer): Integer;
var
  N: Integer;
begin
  if FCount = Length(FKinds) then
  begin
    N := 2 * FCount + 64;
    SetLength(FKinds, N);
    SetLength(FParents, N);
    SetLength(FNexts, N);
    SetLength(FEnds, N);
    SetLength(FAttrCounts, N);
    SetLength(FNameIds, N);
    SetLength(FValues, N);
    SetLength(FLines, N);
    SetLength(FColumns, N);
    SetLength(FDomNodes, N);
    SetLength(FDomAttrs, N);
    SetLength(FDeclFirsts, N);
  end;
  Result := FCount;
  FKinds[Result] := Kind;
  FParents[Result] := -1;
  FNexts[Result] := -1;
  FEnds[Result] := Result;
  FAttrCounts[Result] := 0;
  FNameIds[Result] := -1;
  FValues[Result] := '';
  FLines[Result] := Line;
  FColumns[Result] := Column;
  FDomNodes[Result] := nil;
  FDomAttrs[Result] := -1;
  FDeclFirsts[Result] := -1;
  Inc(FCount);
end;

{ A child of the node on top of the stack. }
procedure TLandrixXmlXPathTree.AddChild(Kind: TLandrixXmlXPathNodeKind; Line, Column: Integer;
  out Index: Integer);
var
  P: Integer;
begin
  Index := NewNode(Kind, Line, Column);
  P := FStack[FDepth - 1];
  FParents[Index] := P;
  if FLastChild[FDepth - 1] >= 0 then
    FNexts[FLastChild[FDepth - 1]] := Index;
  FLastChild[FDepth - 1] := Index;
end;

procedure TLandrixXmlXPathTree.AddText(const Value: TLandrixXmlUtf8; Line, Column: Integer;
  DomNode: TLandrixXmlNode);
var
  I: Integer;
begin
  { no text nodes in the document node, none empty }
  if (FDepth <= 1) or (Value = '') then
    Exit;
  I := FLastChild[FDepth - 1];
  if (I >= 0) and (FKinds[I] = xnkText) then
  begin
    FValues[I] := FValues[I] + Value;
    Exit;
  end;
  AddChild(xnkText, Line, Column, I);
  FValues[I] := Value;
  FDomNodes[I] := DomNode;
end;

procedure TLandrixXmlXPathTree.StartElement(const NamespaceUri, Prefix, LocalName: TLandrixXmlUtf8;
  Line, Column: Integer; DomNode: TLandrixXmlNode);
var
  I: Integer;
begin
  AddChild(xnkElement, Line, Column, I);
  FNameIds[I] := NameId(NamespaceUri, Prefix, LocalName);
  FDomNodes[I] := DomNode;
  if FDepth = Length(FStack) then
  begin
    SetLength(FStack, 2 * FDepth + 16);
    SetLength(FLastChild, 2 * FDepth + 16);
  end;
  FStack[FDepth] := I;
  FLastChild[FDepth] := -1;
  Inc(FDepth);
end;

{ An attribute of the element just started (before its children). }
procedure TLandrixXmlXPathTree.AddAttribute(const NamespaceUri, Prefix, LocalName, Value: TLandrixXmlUtf8;
  DomNode: TLandrixXmlNode; DomIndex: Integer);
var
  E, I: Integer;
begin
  E := FStack[FDepth - 1];
  I := NewNode(xnkAttribute, FLines[E], FColumns[E]);
  FParents[I] := E;
  FNameIds[I] := NameId(NamespaceUri, Prefix, LocalName);
  FValues[I] := Value;
  FDomNodes[I] := DomNode;
  FDomAttrs[I] := DomIndex;
  Inc(FAttrCounts[E]);
end;

{ A namespace declaration of the element just started; xmlns:xml is
  not kept ("xml" is always bound). }
procedure TLandrixXmlXPathTree.AddDeclaration(const Prefix, NamespaceUri: TLandrixXmlUtf8);
var
  E: Integer;
begin
  if Prefix = 'xml' then
    Exit;
  E := FStack[FDepth - 1];
  if FDeclCount = Length(FDeclOwners) then
  begin
    SetLength(FDeclOwners, 2 * FDeclCount + 16);
    SetLength(FDeclPrefixes, 2 * FDeclCount + 16);
    SetLength(FDeclUris, 2 * FDeclCount + 16);
  end;
  if FDeclFirsts[E] < 0 then
    FDeclFirsts[E] := FDeclCount;
  FDeclOwners[FDeclCount] := E;
  FDeclPrefixes[FDeclCount] := Prefix;
  FDeclUris[FDeclCount] := NamespaceUri;
  Inc(FDeclCount);
end;

procedure TLandrixXmlXPathTree.EndElement;
begin
  Dec(FDepth);
  FEnds[FStack[FDepth]] := FCount - 1;
end;

procedure TLandrixXmlXPathTree.Finish;
begin
  FEnds[0] := FCount - 1;
  FStack := nil;
  FLastChild := nil;
  FDepth := 0;
end;

procedure TLandrixXmlXPathTree.LoadFromReader(Reader: TLandrixXmlReader);
var
  I, N: Integer;
begin
  Clear;
  SetLength(FStack, 16);
  SetLength(FLastChild, 16);
  FStack[0] := 0;
  FLastChild[0] := -1;
  FDepth := 1;
  try
    while Reader.Read do
      case Reader.TokenType of
        xttStartElement:
          begin
            StartElement(Reader.NamespaceUriUtf8, Reader.PrefixUtf8, Reader.LocalNameUtf8, Reader.Line,
              Reader.Column, nil);
            { xmlns declares the default namespace, xmlns:p the prefix p }
            for I := 0 to Reader.AttributeCount - 1 do
              if Reader.IsNamespaceDeclaration(I) then
              begin
                if Reader.AttributePrefixSpan(I).Len = 0 then
                  AddDeclaration('', Reader.AttributeValueUtf8(I))
                else
                  AddDeclaration(Reader.AttributeLocalNameUtf8(I), Reader.AttributeValueUtf8(I));
              end;
            for I := 0 to Reader.AttributeCount - 1 do
              if not Reader.IsNamespaceDeclaration(I) then
                AddAttribute(Reader.AttributeNamespaceUriUtf8(I), LandrixXmlSpanToUtf8(Reader.AttributePrefixSpan(I)),
                  Reader.AttributeLocalNameUtf8(I), Reader.AttributeValueUtf8(I), nil, -1);
          end;
        xttEndElement:
          EndElement;
        xttText, xttCData:
          AddText(Reader.ValueUtf8, Reader.Line, Reader.Column, nil);
        xttComment:
          begin
            AddChild(xnkComment, Reader.Line, Reader.Column, N);
            FValues[N] := Reader.ValueUtf8;
          end;
        xttProcessingInstruction:
          begin
            AddChild(xnkProcessingInstruction, Reader.Line, Reader.Column, N);
            FNameIds[N] := NameId('', '', Reader.NameUtf8);
            FValues[N] := Reader.ValueUtf8;
          end;
      else
        { the document type }
      end;
  except
    Clear;
    raise;
  end;
  Finish;
end;

procedure TLandrixXmlXPathTree.LoadFromFile(const FileName: string);
var
  Reader: TLandrixXmlReader;
begin
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromFile(FileName);
    LoadFromReader(Reader);
  finally
    Reader.Free;
  end;
end;

procedure TLandrixXmlXPathTree.LoadFromUtf8(const S: TLandrixXmlUtf8);
var
  Reader: TLandrixXmlReader;
begin
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromUtf8(S);
    LoadFromReader(Reader);
  finally
    Reader.Free;
  end;
end;

procedure TLandrixXmlXPathTree.LoadFromDocument(Document: TLandrixXmlDocument);
var
  Node, Next: TLandrixXmlNode;
  I, N: Integer;
begin
  Clear;
  FDomNodes[0] := Document;
  SetLength(FStack, 16);
  SetLength(FLastChild, 16);
  FStack[0] := 0;
  FLastChild[0] := -1;
  FDepth := 1;
  try
    Node := Document.FirstChild;
    while Node <> nil do
    begin
      case Node.NodeType of
        xntElement:
          begin
            StartElement(Node.NamespaceUriUtf8, Node.PrefixUtf8, Node.LocalNameUtf8, Node.Line, Node.Column, Node);
            for I := 0 to Node.AttributeCount - 1 do
              if Node.IsNamespaceDeclaration(I) then
              begin
                if Node.AttributePrefixUtf8(I) = '' then
                  AddDeclaration('', Node.AttributeValueUtf8(I))
                else
                  AddDeclaration(Node.AttributeLocalNameUtf8(I), Node.AttributeValueUtf8(I));
              end;
            for I := 0 to Node.AttributeCount - 1 do
              if not Node.IsNamespaceDeclaration(I) then
                AddAttribute(Node.AttributeNamespaceUriUtf8(I), Node.AttributePrefixUtf8(I),
                  Node.AttributeLocalNameUtf8(I), Node.AttributeValueUtf8(I), Node, I);
            if Node.FirstChild <> nil then
            begin
              Node := Node.FirstChild;
              Continue;
            end;
            EndElement;
          end;
        xntText, xntCData:
          AddText(Node.ValueUtf8, Node.Line, Node.Column, Node);
        xntComment:
          begin
            AddChild(xnkComment, Node.Line, Node.Column, N);
            FValues[N] := Node.ValueUtf8;
            FDomNodes[N] := Node;
          end;
        xntProcessingInstruction:
          begin
            AddChild(xnkProcessingInstruction, Node.Line, Node.Column, N);
            FNameIds[N] := NameId('', '', Node.NameUtf8);
            FValues[N] := Node.ValueUtf8;
            FDomNodes[N] := Node;
          end;
      else
        { the document type }
      end;
      { the next node in document order, closing finished elements }
      Next := Node.NextSibling;
      while (Next = nil) and (Node.Parent <> nil) and (Node.Parent <> Document) do
      begin
        Node := Node.Parent;
        EndElement;
        Next := Node.NextSibling;
      end;
      Node := Next;
    end;
  except
    Clear;
    raise;
  end;
  Finish;
end;

{ --- namespaces ---------------------------------------------------------- }

{ The element of an element or attribute, -1 for other nodes. }
function TLandrixXmlXPathTree.ElementOf(Index: Integer): Integer;
begin
  Result := Index;
  if FKinds[Result] = xnkAttribute then
    Result := FParents[Result];
  if FKinds[Result] <> xnkElement then
    Result := -1;
end;

{ The declaration of Prefix on Element, -1 if none. }
function TLandrixXmlXPathTree.DeclarationIndex(Element: Integer; const Prefix: TLandrixXmlUtf8): Integer;
begin
  Result := FDeclFirsts[Element];
  if Result < 0 then
    Exit;
  while (Result < FDeclCount) and (FDeclOwners[Result] = Element) do
  begin
    if FDeclPrefixes[Result] = Prefix then
      Exit;
    Inc(Result);
  end;
  Result := -1;
end;

{ Prefix in the name of Element or of one of its attributes, with a
  namespace URI (unprefixed attributes have none). }
function TLandrixXmlXPathTree.NamedPrefixUri(Element: Integer; const Prefix: TLandrixXmlUtf8;
  out NamespaceUri: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  Result := True;
  NamespaceUri := NamespaceUriUtf8(Element);
  if (PrefixUtf8(Element) = Prefix) and (NamespaceUri <> '') then
    Exit;
  if Prefix <> '' then
    for I := Element + 1 to Element + FAttrCounts[Element] do
      if PrefixUtf8(I) = Prefix then
      begin
        NamespaceUri := NamespaceUriUtf8(I);
        Exit;
      end;
  NamespaceUri := '';
  Result := False;
end;

function TLandrixXmlXPathTree.LookupNamespace(Index: Integer; const Prefix: TLandrixXmlUtf8;
  out NamespaceUri: TLandrixXmlUtf8): Boolean;
var
  E, N, D: Integer;
begin
  NamespaceUri := '';
  Result := False;
  E := ElementOf(Index);
  if (E < 0) or (Prefix = 'xmlns') then
    Exit;
  if Prefix = 'xml' then
  begin
    NamespaceUri := LandrixXmlNamespaceXml;
    Result := True;
    Exit;
  end;
  { the parent of the root element is the document node 0 }
  N := E;
  while N > 0 do
  begin
    D := DeclarationIndex(N, Prefix);
    if D >= 0 then
    begin
      NamespaceUri := FDeclUris[D];
      Result := NamespaceUri <> '';
      Exit;
    end;
    N := FParents[N];
  end;
  N := E;
  while N > 0 do
  begin
    if NamedPrefixUri(N, Prefix, NamespaceUri) then
    begin
      Result := True;
      Exit;
    end;
    N := FParents[N];
  end;
end;

function HasPrefix(const List: TLandrixXmlUtf8Array; Count: Integer; const S: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 0 to Count - 1 do
    if List[I] = S then
      Exit;
  Result := False;
end;

procedure AddPrefix(var List: TLandrixXmlUtf8Array; var Count: Integer; const S: TLandrixXmlUtf8);
begin
  if Count = Length(List) then
    SetLength(List, 2 * Count + 8);
  List[Count] := S;
  Inc(Count);
end;

function TLandrixXmlXPathTree.InScopePrefixesUtf8(Index: Integer): TLandrixXmlUtf8Array;
var
  Seen: TLandrixXmlUtf8Array;
  E, N, D, I, Count, SeenCount: Integer;
  P: TLandrixXmlUtf8;
begin
  Result := nil;
  E := ElementOf(Index);
  if E < 0 then
    Exit;
  Seen := nil;
  Count := 0;
  SeenCount := 0;
  { the nearest declaration of a prefix counts, xmlns="" included }
  N := E;
  while N > 0 do
  begin
    D := FDeclFirsts[N];
    if D >= 0 then
      while (D < FDeclCount) and (FDeclOwners[D] = N) do
      begin
        if not HasPrefix(Seen, SeenCount, FDeclPrefixes[D]) then
        begin
          AddPrefix(Seen, SeenCount, FDeclPrefixes[D]);
          if FDeclUris[D] <> '' then
            AddPrefix(Result, Count, FDeclPrefixes[D]);
        end;
        Inc(D);
      end;
    N := FParents[N];
  end;
  { then the prefixes of names without a declaration, as LookupNamespace }
  N := E;
  while N > 0 do
  begin
    for I := N to N + FAttrCounts[N] do
    begin
      P := PrefixUtf8(I);
      if ((I = N) or (P <> '')) and (P <> 'xml') and (NamespaceUriUtf8(I) <> '') and
        not HasPrefix(Seen, SeenCount, P) then
      begin
        AddPrefix(Seen, SeenCount, P);
        AddPrefix(Result, Count, P);
      end;
    end;
    N := FParents[N];
  end;
  AddPrefix(Result, Count, 'xml');
  SetLength(Result, Count);
end;

function TLandrixXmlXPathTree.GetKind(Index: Integer): TLandrixXmlXPathNodeKind;
begin
  Result := FKinds[Index];
end;

function TLandrixXmlXPathTree.GetParent(Index: Integer): Integer;
begin
  Result := FParents[Index];
end;

function TLandrixXmlXPathTree.GetNextSibling(Index: Integer): Integer;
begin
  Result := FNexts[Index];
end;

function TLandrixXmlXPathTree.GetSubtreeEnd(Index: Integer): Integer;
begin
  Result := FEnds[Index];
end;

function TLandrixXmlXPathTree.GetAttributeCount(Index: Integer): Integer;
begin
  Result := FAttrCounts[Index];
end;

function TLandrixXmlXPathTree.FirstChild(Index: Integer): Integer;
begin
  Result := Index + FAttrCounts[Index] + 1;
  if (FKinds[Index] in [xnkAttribute, xnkText, xnkComment, xnkProcessingInstruction]) or
    (Result > FEnds[Index]) then
    Result := -1;
end;

function TLandrixXmlXPathTree.DocumentElement: Integer;
begin
  Result := FirstChild(0);
  while (Result >= 0) and (FKinds[Result] <> xnkElement) do
    Result := FNexts[Result];
end;

function TLandrixXmlXPathTree.GetExpandedName(Index: Integer): Integer;
begin
  if FNameIds[Index] < 0 then
    Result := -1
  else
    Result := FNameExpanded[FNameIds[Index]];
end;

function TLandrixXmlXPathTree.FindExpandedName(const NamespaceUri, LocalName: TLandrixXmlUtf8): Integer;
begin
  Result := LookupExpanded(NamespaceUri + #0 + LocalName, False);
end;

function TLandrixXmlXPathTree.LocalNameUtf8(Index: Integer): TLandrixXmlUtf8;
begin
  if FNameIds[Index] < 0 then
    Result := ''
  else
    Result := FNameLocals[FNameIds[Index]];
end;

function TLandrixXmlXPathTree.NamespaceUriUtf8(Index: Integer): TLandrixXmlUtf8;
begin
  if FNameIds[Index] < 0 then
    Result := ''
  else
    Result := FNameUris[FNameIds[Index]];
end;

function TLandrixXmlXPathTree.PrefixUtf8(Index: Integer): TLandrixXmlUtf8;
begin
  if FNameIds[Index] < 0 then
    Result := ''
  else
    Result := FNamePrefixes[FNameIds[Index]];
end;

function TLandrixXmlXPathTree.NameUtf8(Index: Integer): TLandrixXmlUtf8;
begin
  Result := PrefixUtf8(Index);
  if Result <> '' then
    Result := Result + ':' + LocalNameUtf8(Index)
  else
    Result := LocalNameUtf8(Index);
end;

function TLandrixXmlXPathTree.ValueUtf8(Index: Integer): TLandrixXmlUtf8;
begin
  Result := FValues[Index];
end;

function TLandrixXmlXPathTree.StringValueUtf8(Index: Integer): TLandrixXmlUtf8;
var
  I, N, Len: Integer;
begin
  if not (FKinds[Index] in [xnkDocument, xnkElement]) then
  begin
    Result := FValues[Index];
    Exit;
  end;
  { one text node is common: no copy }
  N := -1;
  Len := 0;
  for I := Index + 1 to FEnds[Index] do
    if FKinds[I] = xnkText then
    begin
      if N = -1 then
        N := I
      else
        N := -2;
      Inc(Len, Length(FValues[I]));
    end;
  if N >= 0 then
  begin
    Result := FValues[N];
    Exit;
  end;
  Result := '';
  if Len = 0 then
    Exit;
  SetLength(Result, Len);
  Len := 0;
  for I := Index + 1 to FEnds[Index] do
    if (FKinds[I] = xnkText) and (FValues[I] <> '') then
    begin
      { PAnsiChar, not FValues[I][1]: that would make the string unique, a
        write to a tree other threads may read }
      Move(PAnsiChar(FValues[I])^, Result[Len + 1], Length(FValues[I]));
      Inc(Len, Length(FValues[I]));
    end;
end;

{ The positions of all children of Parent: per kind (and expanded name
  for elements and processing instructions) counted from 1. }
procedure TLandrixXmlXPathTree.ComputePositions(Parent: Integer);
var
  Elements, Instructions: TLandrixXmlXPathIntArray;
  P, E, Texts, Comments: Integer;
begin
  if Length(FPositions) < FCount then
  begin
    E := Integer(Length(FPositions));
    SetLength(FPositions, FCount);
    for P := E to FCount - 1 do
      FPositions[P] := 0;
  end;
  Elements := nil;
  Instructions := nil;
  SetLength(Elements, FExpandedCount);
  SetLength(Instructions, FExpandedCount);
  for P := 0 to FExpandedCount - 1 do
  begin
    Elements[P] := 0;
    Instructions[P] := 0;
  end;
  Texts := 0;
  Comments := 0;
  P := FirstChild(Parent);
  while P >= 0 do
  begin
    case FKinds[P] of
      xnkElement:
        begin
          E := FNameExpanded[FNameIds[P]];
          Inc(Elements[E]);
          FPositions[P] := Elements[E];
        end;
      xnkProcessingInstruction:
        begin
          E := FNameExpanded[FNameIds[P]];
          Inc(Instructions[E]);
          FPositions[P] := Instructions[E];
        end;
      xnkText:
        begin
          Inc(Texts);
          FPositions[P] := Texts;
        end;
      xnkComment:
        begin
          Inc(Comments);
          FPositions[P] := Comments;
        end;
    else
      { attributes are not children }
    end;
    P := FNexts[P];
  end;
end;

function TLandrixXmlXPathTree.LocationPathUtf8(Index: Integer): TLandrixXmlUtf8;
var
  I: Integer;
  Segment: TLandrixXmlUtf8;
begin
  Result := '';
  I := Index;
  while (I > 0) and (FKinds[I] <> xnkDocument) do
  begin
    Segment := '';
    if FKinds[I] = xnkAttribute then
      Segment := '@Q{' + NamespaceUriUtf8(I) + '}' + LocalNameUtf8(I)
    else
    begin
      { the position among the preceding siblings of the same kind (and
        name), as xsl:number level="single" counts }
      if (I >= Length(FPositions)) or (FPositions[I] = 0) then
        ComputePositions(FParents[I]);
      case FKinds[I] of
        xnkElement:
          Segment := 'Q{' + NamespaceUriUtf8(I) + '}' + LocalNameUtf8(I);
        xnkText:
          Segment := 'text()';
        xnkComment:
          Segment := 'comment()';
      else
        Segment := 'processing-instruction("' + LocalNameUtf8(I) + '")';
      end;
      Segment := Segment + '[' + LandrixXmlStringToUtf8(IntToStr(FPositions[I])) + ']';
    end;
    Result := '/' + Segment + Result;
    I := FParents[I];
  end;
  if Result = '' then
    Result := '/';
end;

function TLandrixXmlXPathTree.GetLine(Index: Integer): Integer;
begin
  Result := FLines[Index];
end;

function TLandrixXmlXPathTree.GetColumn(Index: Integer): Integer;
begin
  Result := FColumns[Index];
end;

function TLandrixXmlXPathTree.GetDomNode(Index: Integer): TLandrixXmlNode;
begin
  Result := FDomNodes[Index];
end;

function TLandrixXmlXPathTree.GetDomAttributeIndex(Index: Integer): Integer;
begin
  Result := FDomAttrs[Index];
end;

end.
