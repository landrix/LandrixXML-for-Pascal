{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Validates documents against a loaded XML Schema (LandrixXmlXsdSchema):
  element and attribute declarations, simple and complex types, content
  models, fixed and default values, ID and IDREF, identity constraints.

  One validation core is driven by start tag, text and end tag events,
  either from the pull reader while the document is read
  (ValidateFile, ValidateReader) or from a loaded DOM (ValidateDocument).
  The errors follow the validator of the Java runtime (Xerces, which the
  KoSIT validator uses): the same cvc codes, messages, order and recovery
  after an error. With the reader the positions are those Xerces reports
  (right after the start or end tag where the error is found); with the
  DOM they are the start of the node the error belongs to. Every error
  also has a path such as /Invoice/cac:InvoiceLine[2]/cbc:ID[1] (names as
  written, indices counted among siblings of the same expanded name) and
  the schema file and line of the declaration concerned.

  An element without a declaration (unknown root, not allowed by the
  content model, or matched by a lax or strict wildcard) is assessed
  laxly with anyType, as Xerces does: its children and attributes are
  validated where global declarations exist. Content of a skip wildcard
  is not looked at.

  The identity constraint matching (XPathMatcher, value stores) is ported
  from Apache Xerces-J 2.12.2, Apache License 2.0; see
  THIRD-PARTY-NOTICES.md and LICENSES/Apache-2.0.txt.

  Identity constraints (unique, key, keyref) are checked as Xerces does,
  including its quirks: names without prefix in selectors and fields
  have no namespace; the value tables of a key are collected per depth
  and merged towards the root as elements end, and a keyref sees the
  tables of its own element and its descendants. A keyref whose key is
  not in that range is reported with the code "KeyRefOutOfScope" (Xerces
  has no cvc code for it); the message names the constraint where Xerces
  prints a Java object name such as "KeyRef@4f47d241".

  xsi:type replaces the declared type (cvc-elt.4), xsi:nil marks an
  element of a nillable declaration as empty (cvc-elt.3), as in Xerces.
  An xsi:type naming a built-in type that is not supported (duration,
  NOTATION, ENTITY, ENTITIES) is reported with the code "unsupported"
  (never silently accepted). Default values are used for validation but
  never written into the document. }

unit LandrixXmlXsdValidator;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  Classes,
  Contnrs,
  LandrixXmlBase,
  LandrixXmlReader,
  LandrixXmlDom,
  LandrixXmlXsdTypes,
  LandrixXmlXsdContent,
  LandrixXmlXsdSchema;

const
  LandrixXmlXsiNamespace = 'http://www.w3.org/2001/XMLSchema-instance';

type
  TLandrixXmlXsdValidationError = class
  private
    FCode: string;
    FMessage: string;
    FLine: Integer;
    FColumn: Integer;
    FPath: TLandrixXmlUtf8;
    FSchemaFile: string;
    FSchemaLine: Integer;
    FNode: TLandrixXmlNode;
  public
    { the Xerces code such as cvc-complex-type.2.4.a, "KeyRefOutOfScope"
      or "unsupported" }
    property Code: string read FCode;
    { English, in Xerces' wording; non-ASCII characters as U+XXXX }
    property Message: string read FMessage;
    property Line: Integer read FLine;
    property Column: Integer read FColumn;
    property Path: TLandrixXmlUtf8 read FPath;
    { the declaration or type concerned; '' and 0 if there is none }
    property SchemaFile: string read FSchemaFile;
    property SchemaLine: Integer read FSchemaLine;
    { the element the error belongs to (DOM validation only) }
    property Node: TLandrixXmlNode read FNode;
  end;

  { Internal, public only because Delphi 6 has no nested types.
    xfmLax: no declaration, assessed with anyType; xfmSkip: not looked at. }
  TLandrixXmlXsdFrameMode = (xfmValidate, xfmLax, xfmSkip);
  TLandrixXmlXsdChildCount = record
    NamespaceUri: TLandrixXmlUtf8;
    LocalName: TLandrixXmlUtf8;
    Count: Integer;
  end;
  TLandrixXmlXsdChildCounts = array of TLandrixXmlXsdChildCount;
  TLandrixXmlXsdFrame = record
    Mode: TLandrixXmlXsdFrameMode;
    Decl: TLandrixXmlXsdElementDecl;
    ComplexType: TLandrixXmlXsdComplexType;
    SimpleType: TLandrixXmlXsdSimpleType;
    State: TLandrixXmlXsdContentState;
    Name: TLandrixXmlUtf8;
    NamespaceUri: TLandrixXmlUtf8;
    LocalName: TLandrixXmlUtf8;
    PathStep: TLandrixXmlUtf8;
    { the element's validated value, for identity constraint fields }
    ValueKnown: Boolean;
    ValueKey: TLandrixXmlUtf8;
    ValueText: TLandrixXmlUtf8;
    HasChild: Boolean;
    HasText: Boolean;
    HasNonSpaceText: Boolean;
    { xsi:nil="true" on an element of a nillable declaration }
    Nilled: Boolean;
    Node: TLandrixXmlNode;
    Children: TLandrixXmlXsdChildCounts;
    ChildKinds: Integer;
  end;
  TLandrixXmlXsdFrames = array of TLandrixXmlXsdFrame;
  TLandrixXmlXsdEventAttribute = record
    NamespaceUri: TLandrixXmlUtf8;
    LocalName: TLandrixXmlUtf8;
    Name: TLandrixXmlUtf8;
    Value: TLandrixXmlUtf8;
  end;
  TLandrixXmlXsdEventAttributes = array of TLandrixXmlXsdEventAttribute;

  TLandrixXmlXsdValidator = class
  private
    FSchema: TLandrixXmlXsdSchemaSet;
    FErrors: TObjectList;
    FMaxErrors: Integer;
    FTruncated: Boolean;
    FFrames: TLandrixXmlXsdFrames;
    FDepth: Integer;
    FStates: TObjectList;
    FAttrs: TLandrixXmlXsdEventAttributes;
    FAttrCount: Integer;
    FIds: TLandrixXmlXsdNameMap;
    FIdRefs: TLandrixXmlUtf8Array;
    FIdRefCount: Integer;
    FExpected: TList;
    FIdType: TLandrixXmlXsdSimpleType;
    FIdRefType: TLandrixXmlXsdSimpleType;
    FQNameType: TLandrixXmlXsdSimpleType;
    FBooleanType: TLandrixXmlXsdSimpleType;
    FAttrValues: TLandrixXmlXsdValueArray;
    FAttrValid: array of Boolean;
    { the text of the current element as Xerces buffers it }
    FBuffer: TLandrixXmlUtf8;
    FAppendBuffer: Boolean;
    { identity constraints: value stores, matchers, the keys in scope }
    FStores: TObjectList;
    FStoreIndex: TLandrixXmlXsdNameMap;
    FMatchers: TObjectList;
    FContexts: array of Integer;
    FContextCount: Integer;
    FGlobal: TObject;
    { the namespace context of QName values: the reader's, or that of the
      current DOM element }
    FValueContext: TLandrixXmlXsdNamespaceContext;
    FMapStack: TObjectList;
    FIdcLine: Integer;
    FIdcColumn: Integer;
    function GetErrorCount: Integer;
    function GetError(Index: Integer): TLandrixXmlXsdValidationError;
    procedure Reset;
    function Stopped: Boolean;
    procedure AddError(const Code, Message: string; Line, Column: Integer;
      const Path: TLandrixXmlUtf8; const SchemaFile: string; SchemaLine: Integer; Node: TLandrixXmlNode);
    function CurrentPath: TLandrixXmlUtf8;
    function ChildPathStep(const NamespaceUri, LocalName, Name: TLandrixXmlUtf8): TLandrixXmlUtf8;
    procedure Report(const Code, Message: string; Line, Column: Integer; Component: TLandrixXmlXsdComponent);
    procedure ClearAttributes;
    procedure AddAttribute(const NamespaceUri, LocalName, Name, Value: TLandrixXmlUtf8);
    procedure StartElement(const NamespaceUri, LocalName, Name: TLandrixXmlUtf8; Line, Column: Integer;
      Node: TLandrixXmlNode);
    procedure Text(const Value: TLandrixXmlUtf8; IsWhitespace: Boolean);
    procedure EndElement(Line, Column: Integer);
    procedure EndDocument(Line, Column: Integer);
    procedure CheckAttributes(var F: TLandrixXmlXsdFrame; Line, Column: Integer);
    function FindXsi(const LocalName: TLandrixXmlUtf8; out Value: TLandrixXmlUtf8): Boolean;
    procedure ApplyXsiType(const Text, Name: TLandrixXmlUtf8; Decl: TLandrixXmlXsdElementDecl;
      var CT: TLandrixXmlXsdComplexType; var ST: TLandrixXmlXsdSimpleType; Line, Column: Integer);
    function DefaultValidFor(CT: TLandrixXmlXsdComplexType; ST: TLandrixXmlXsdSimpleType;
      const Text: TLandrixXmlUtf8): Boolean;
    procedure AddDefaultAttributes(T: TLandrixXmlXsdComplexType);
    function CheckIdValue(T: TLandrixXmlXsdSimpleType; const Value: TLandrixXmlXsdValue; Line, Column: Integer): Boolean;
    function CheckIdItem(Member: TLandrixXmlXsdSimpleType; const Text: TLandrixXmlUtf8;
      Line, Column: Integer): Boolean;
    function NewState: TLandrixXmlXsdContentState;
    procedure IdcError(const Code, Message: string; C: TLandrixXmlXsdIdentityConstraint);
    function StoreFor(C: TLandrixXmlXsdIdentityConstraint; Depth: Integer): TObject;
    procedure MatcherStart(Matcher: TObject; const NamespaceUri, LocalName: TLandrixXmlUtf8);
    procedure MatcherEnd(Matcher: TObject);
    procedure SelectorStart(Matcher: TObject; const NamespaceUri, LocalName: TLandrixXmlUtf8);
    procedure SelectorEnd(Matcher: TObject);
    procedure FieldMatched(Matcher: TObject; const Key, Text: TLandrixXmlUtf8);
    procedure EndValueScope(Store: TObject);
    procedure CheckKeyRef(Store: TObject);
    procedure IdentityStart(Line, Column: Integer);
    procedure IdentityEnd(Line, Column: Integer);
  public
    { The schema is not owned; it must live as long as the validator. }
    constructor Create(Schema: TLandrixXmlXsdSchemaSet);
    destructor Destroy; override;
    { Reads and validates the file; malformed XML raises ELandrixXmlError
      as when reading. True if there is no error. }
    function ValidateFile(const FileName: string): Boolean;
    { Validates the document that Reader is about to read (Read is called
      until the end). }
    function ValidateReader(Reader: TLandrixXmlReader): Boolean;
    { Validates a loaded document. The positions are the starts of the
      nodes, and every error has the element it belongs to as Node. }
    function ValidateDocument(Document: TLandrixXmlDocument): Boolean;
    property ErrorCount: Integer read GetErrorCount;
    property Errors[Index: Integer]: TLandrixXmlXsdValidationError read GetError;
    { at most this many errors are collected (0 = no limit, the default
      is 1000); then validation stops and Truncated is True }
    property MaxErrors: Integer read FMaxErrors write FMaxErrors;
    property Truncated: Boolean read FTruncated;
    property Schema: TLandrixXmlXsdSchemaSet read FSchema;
  end;

implementation

type
  { the namespace declarations in scope at the current element: those of
    the DOM node if there is one, else those of the reader }
  TValueContext = class(TLandrixXmlXsdNamespaceContext)
  public
    Reader: TLandrixXmlReader;
    Node: TLandrixXmlNode;
    function LookupNamespace(const Prefix: TLandrixXmlUtf8; out NamespaceUri: TLandrixXmlUtf8): Boolean;
      override;
  end;

function TValueContext.LookupNamespace(const Prefix: TLandrixXmlUtf8; out NamespaceUri: TLandrixXmlUtf8): Boolean;
begin
  NamespaceUri := '';
  if Node <> nil then
    Result := Node.LookupNamespace(Prefix, NamespaceUri)
  else if Reader <> nil then
    Result := Reader.LookupNamespace(Prefix, NamespaceUri)
  else
    Result := False;
end;

{ Names and values are quoted whole, as Xerces does. }
function Q(const S: TLandrixXmlUtf8): string;
begin
  Result := '''' + LandrixXmlEscapeForMessage(S, MaxInt) + '''';
end;

function IsSpaceText(const S: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    if not (S[I] in [' ', #9, #10, #13]) then
    begin
      Result := False;
      Exit;
    end;
  Result := True;
end;

function PointerText(P: Pointer): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(Format('%p', [P]));
end;

{ --- identity constraints: data ------------------------------------------ }

{ The checks follow Xerces closely (its value stores, the maps of the keys
  in scope and its XPath matchers), so that the same errors are reported
  at the same places. }

const
  IdcMatched = 1;
  IdcMatchedAttribute = 3;
  IdcMatchedDescendant = 5;
  IdcMatchedDescendantPrevious = 13;

type
  TIdcAxis = (iaSelf, iaDescendant, iaChild, iaAttribute);
  TIdcIntArray = array of Integer;

  { The values of one identity constraint for the scope element at one
    depth (Xerces reuses the store for the next element at that depth). }
  TIdcStore = class
    Constraint: TLandrixXmlXsdIdentityConstraint;
    FieldCount: Integer;
    ElementName: TLandrixXmlUtf8;
    { the tuple of the current target; the key '' is a missing value
      (invalid or not simple), which Xerces keeps as null }
    LocalKeys: TLandrixXmlUtf8Array;
    LocalTexts: TLandrixXmlUtf8Array;
    ValuesCount: Integer;
    { a value was ever counted (the JDK's fHasValue, never reset) }
    HasValue: Boolean;
    { the complete tuples, also those appended from other stores }
    TupleKeys: TLandrixXmlUtf8Array;
    TupleTexts: TLandrixXmlUtf8Array;
    TupleCount: Integer;
    Tuples: TLandrixXmlXsdNameMap;
    constructor Create(C: TLandrixXmlXsdIdentityConstraint; const AElementName: TLandrixXmlUtf8);
    destructor Destroy; override;
    procedure Clear;
    procedure StartValueScope;
    procedure AddTuple(const Key, Text: TLandrixXmlUtf8);
    procedure Append(Other: TIdcStore);
  end;

  { Constraints mapped to value stores; small, searched linearly. }
  TIdcMap = class
    Constraints: TList;
    Stores: TList;
    constructor Create;
    destructor Destroy; override;
    function Find(C: TLandrixXmlXsdIdentityConstraint): TIdcStore;
    procedure Put(C: TLandrixXmlXsdIdentityConstraint; S: TIdcStore);
    procedure Assign(Other: TIdcMap);
    procedure Clear;
  end;

  { A selector or field being matched, as Xerces' XPathMatcher: per
    alternative the current step, a stack of steps, a depth without match
    and the kind of match. }
  TIdcMatcher = class
    IsSelector: Boolean;
    Constraint: TLandrixXmlXsdIdentityConstraint;
    Paths: TLandrixXmlXsdPaths;
    Field: Integer;
    Store: TIdcStore;
    MayMatch: Boolean;
    InitialDepth: Integer;
    ElementDepth: Integer;
    MatchedDepth: Integer;
    Matched: TIdcIntArray;
    CurrentStep: TIdcIntArray;
    NoMatchDepth: TIdcIntArray;
    Stacks: array of TIdcIntArray;
    StackCounts: TIdcIntArray;
    constructor Create(const APaths: TLandrixXmlXsdPaths);
  end;

constructor TIdcStore.Create(C: TLandrixXmlXsdIdentityConstraint; const AElementName: TLandrixXmlUtf8);
begin
  inherited Create;
  Constraint := C;
  ElementName := AElementName;
  FieldCount := Integer(Length(C.Fields));
  SetLength(LocalKeys, FieldCount);
  SetLength(LocalTexts, FieldCount);
  Tuples := TLandrixXmlXsdNameMap.Create;
end;

destructor TIdcStore.Destroy;
begin
  Tuples.Free;
  inherited Destroy;
end;

procedure TIdcStore.Clear;
begin
  ValuesCount := 0;
  TupleKeys := nil;
  TupleTexts := nil;
  TupleCount := 0;
  Tuples.Free;
  Tuples := TLandrixXmlXsdNameMap.Create;
end;

procedure TIdcStore.StartValueScope;
var
  I: Integer;
begin
  ValuesCount := 0;
  for I := 0 to FieldCount - 1 do
  begin
    LocalKeys[I] := '';
    LocalTexts[I] := 'null';
  end;
end;

procedure TIdcStore.AddTuple(const Key, Text: TLandrixXmlUtf8);
begin
  if TupleCount = Length(TupleKeys) then
  begin
    SetLength(TupleKeys, 2 * TupleCount + 8);
    SetLength(TupleTexts, 2 * TupleCount + 8);
  end;
  TupleKeys[TupleCount] := Key;
  TupleTexts[TupleCount] := Text;
  Inc(TupleCount);
  Tuples.Add('', Key, Self);
end;

procedure TIdcStore.Append(Other: TIdcStore);
var
  I: Integer;
begin
  if Other = Self then
    Exit;
  for I := 0 to Other.TupleCount - 1 do
    AddTuple(Other.TupleKeys[I], Other.TupleTexts[I]);
end;

constructor TIdcMap.Create;
begin
  inherited Create;
  Constraints := TList.Create;
  Stores := TList.Create;
end;

destructor TIdcMap.Destroy;
begin
  Constraints.Free;
  Stores.Free;
  inherited Destroy;
end;

function TIdcMap.Find(C: TLandrixXmlXsdIdentityConstraint): TIdcStore;
var
  I: Integer;
begin
  for I := 0 to Integer(Constraints.Count) - 1 do
    if Constraints[I] = C then
    begin
      Result := TIdcStore(Stores[I]);
      Exit;
    end;
  Result := nil;
end;

procedure TIdcMap.Put(C: TLandrixXmlXsdIdentityConstraint; S: TIdcStore);
var
  I: Integer;
begin
  for I := 0 to Integer(Constraints.Count) - 1 do
    if Constraints[I] = C then
    begin
      Stores[I] := S;
      Exit;
    end;
  Constraints.Add(C);
  Stores.Add(S);
end;

procedure TIdcMap.Assign(Other: TIdcMap);
var
  I: Integer;
begin
  Clear;
  for I := 0 to Integer(Other.Constraints.Count) - 1 do
  begin
    Constraints.Add(Other.Constraints[I]);
    Stores.Add(Other.Stores[I]);
  end;
end;

procedure TIdcMap.Clear;
begin
  Constraints.Clear;
  Stores.Clear;
end;

constructor TIdcMatcher.Create(const APaths: TLandrixXmlXsdPaths);
var
  N: Integer;
begin
  inherited Create;
  Paths := APaths;
  N := Integer(Length(APaths));
  SetLength(Matched, N);
  SetLength(CurrentStep, N);
  SetLength(NoMatchDepth, N);
  SetLength(Stacks, N);
  SetLength(StackCounts, N);
  MayMatch := True;
  MatchedDepth := -1;
end;

{ Xerces' steps of a path: "." first (it prefixes "./"), then "//" for a
  leading ".//", then the child and attribute steps. }
function StepCount(const Path: TLandrixXmlXsdPath): Integer;
begin
  Result := 1 + Ord(Path.Descendant) + Integer(Length(Path.Steps));
end;

function AxisAt(const Path: TLandrixXmlXsdPath; K: Integer): TIdcAxis;
begin
  if K = 0 then
    Result := iaSelf
  else if Path.Descendant and (K = 1) then
    Result := iaDescendant
  else if Path.Steps[K - 1 - Ord(Path.Descendant)].IsAttribute then
    Result := iaAttribute
  else
    Result := iaChild;
end;

function StepMatches(const Step: TLandrixXmlXsdPathStep; const NamespaceUri, LocalName: TLandrixXmlUtf8): Boolean;
begin
  if Step.AnyName then
    Result := True
  else if Step.AnyLocalName then
    Result := NamespaceUri = Step.NamespaceUri
  else
    Result := (LocalName = Step.LocalName) and (NamespaceUri = Step.NamespaceUri);
end;

function StepAtMatches(const Path: TLandrixXmlXsdPath; K: Integer; const NamespaceUri,
  LocalName: TLandrixXmlUtf8): Boolean;
begin
  Result := StepMatches(Path.Steps[K - 1 - Ord(Path.Descendant)], NamespaceUri, LocalName);
end;

{ How Xerces prints a field: "./" or ".//" and the steps as written. }
function FieldText(C: TLandrixXmlXsdIdentityConstraint; Field: Integer): string;
var
  I, K: Integer;
  S: TLandrixXmlUtf8;
begin
  S := '';
  for I := 0 to Integer(Length(C.Fields[Field])) - 1 do
  begin
    if I > 0 then
      S := S + '|';
    S := S + '.';
    if C.Fields[Field][I].Descendant then
      S := S + '//';
    for K := 0 to Integer(Length(C.Fields[Field][I].Steps)) - 1 do
    begin
      if (K > 0) or not C.Fields[Field][I].Descendant then
        S := S + '/';
      if C.Fields[Field][I].Steps[K].IsAttribute then
        S := S + '@';
      S := S + C.Fields[Field][I].Steps[K].Text;
    end;
  end;
  Result := LandrixXmlEscapeForMessage(S, MaxInt);
end;

{ --- identity constraints: Xerces' matchers and value stores ------------- }

procedure TLandrixXmlXsdValidator.IdcError(const Code, Message: string; C: TLandrixXmlXsdIdentityConstraint);
begin
  AddError(Code, Message, FIdcLine, FIdcColumn, CurrentPath, C.SchemaFile, C.SchemaLine, nil);
end;

{ The store of C for the scope element at Depth, emptied when it is
  reused (Xerces keys its stores by constraint and depth). }
function TLandrixXmlXsdValidator.StoreFor(C: TLandrixXmlXsdIdentityConstraint; Depth: Integer): TObject;
var
  Key: TLandrixXmlUtf8;
  S: TIdcStore;
begin
  Key := PointerText(C) + '/' + LandrixXmlStringToUtf8(IntToStr(Depth));
  S := TIdcStore(FStoreIndex.Find('', Key));
  if S = nil then
  begin
    S := TIdcStore.Create(C, FFrames[Depth].LocalName);
    FStores.Add(S);
    FStoreIndex.Add('', Key, S);
  end
  else
    S.Clear;
  Result := S;
end;

{ XPathMatcher.startElement of Xerces. }
procedure TLandrixXmlXsdValidator.MatcherStart(Matcher: TObject; const NamespaceUri, LocalName: TLandrixXmlUtf8);
var
  M: TIdcMatcher;
  I, J, A, N, StartStep, DescendantStep: Integer;
  SawDescendant: Boolean;
begin
  M := TIdcMatcher(Matcher);
  for I := 0 to Integer(Length(M.Paths)) - 1 do
  begin
    StartStep := M.CurrentStep[I];
    if M.StackCounts[I] = Length(M.Stacks[I]) then
      SetLength(M.Stacks[I], 2 * M.StackCounts[I] + 4);
    M.Stacks[I][M.StackCounts[I]] := StartStep;
    Inc(M.StackCounts[I]);
    if ((M.Matched[I] and IdcMatchedDescendant) = IdcMatched) or (M.NoMatchDepth[I] > 0) then
    begin
      Inc(M.NoMatchDepth[I]);
      Continue;
    end;
    if (M.Matched[I] and IdcMatchedDescendant) = IdcMatchedDescendant then
      M.Matched[I] := IdcMatchedDescendantPrevious;
    N := StepCount(M.Paths[I]);
    while (M.CurrentStep[I] < N) and (AxisAt(M.Paths[I], M.CurrentStep[I]) = iaSelf) do
      Inc(M.CurrentStep[I]);
    if M.CurrentStep[I] = N then
    begin
      M.Matched[I] := IdcMatched;
      Continue;
    end;
    DescendantStep := M.CurrentStep[I];
    while (M.CurrentStep[I] < N) and (AxisAt(M.Paths[I], M.CurrentStep[I]) = iaDescendant) do
      Inc(M.CurrentStep[I]);
    SawDescendant := M.CurrentStep[I] > DescendantStep;
    if M.CurrentStep[I] = N then
    begin
      Inc(M.NoMatchDepth[I]);
      Continue;
    end;
    if ((M.CurrentStep[I] = StartStep) or (M.CurrentStep[I] > DescendantStep)) and
      (AxisAt(M.Paths[I], M.CurrentStep[I]) = iaChild) then
    begin
      if not StepAtMatches(M.Paths[I], M.CurrentStep[I], NamespaceUri, LocalName) then
      begin
        if M.CurrentStep[I] > DescendantStep then
        begin
          M.CurrentStep[I] := DescendantStep;
          Continue;
        end;
        Inc(M.NoMatchDepth[I]);
        Continue;
      end;
      Inc(M.CurrentStep[I]);
    end;
    if M.CurrentStep[I] = N then
    begin
      if SawDescendant then
      begin
        M.CurrentStep[I] := DescendantStep;
        M.Matched[I] := IdcMatchedDescendant;
      end
      else
        M.Matched[I] := IdcMatched;
      Continue;
    end;
    if AxisAt(M.Paths[I], M.CurrentStep[I]) = iaAttribute then
    begin
      for A := 0 to FAttrCount - 1 do
        if StepAtMatches(M.Paths[I], M.CurrentStep[I], FAttrs[A].NamespaceUri, FAttrs[A].LocalName) then
        begin
          Inc(M.CurrentStep[I]);
          if M.CurrentStep[I] = N then
          begin
            M.Matched[I] := IdcMatchedAttribute;
            J := 0;
            while (J < I) and ((M.Matched[J] and IdcMatched) <> IdcMatched) do
              Inc(J);
            if (J = I) and not M.IsSelector then
            begin
              { Xerces deviation: idZ015. An attribute without a type (matched
                by a lax or skip wildcard) still gives a field value }
              if FAttrValid[A] then
                FieldMatched(M, LandrixXmlXsdValueKey(FAttrValues[A]), LandrixXmlXsdValueText(FAttrValues[A]))
              else
                FieldMatched(M, '', 'null');
            end;
          end;
          { Xerces deviation: idL100. A step @* matches the first attribute
            only, so a second one (also xsi:nil) is no second value }
          Break;
        end;
      if (M.Matched[I] and IdcMatched) <> IdcMatched then
      begin
        if M.CurrentStep[I] > DescendantStep then
        begin
          M.CurrentStep[I] := DescendantStep;
          Continue;
        end;
        Inc(M.NoMatchDepth[I]);
      end;
    end;
  end;
end;

{ XPathMatcher.endElement of Xerces; a field takes the value of the
  element at the top of the stack (Field.Matcher.handleContent). }
procedure TLandrixXmlXsdValidator.MatcherEnd(Matcher: TObject);
var
  M: TIdcMatcher;
  I, J, Top: Integer;
  T: TLandrixXmlXsdComplexType;
begin
  M := TIdcMatcher(Matcher);
  Top := FDepth - 1;
  for I := 0 to Integer(Length(M.Paths)) - 1 do
  begin
    Dec(M.StackCounts[I]);
    M.CurrentStep[I] := M.Stacks[I][M.StackCounts[I]];
    if M.NoMatchDepth[I] > 0 then
    begin
      Dec(M.NoMatchDepth[I]);
      Continue;
    end;
    J := 0;
    while (J < I) and ((M.Matched[J] and IdcMatched) <> IdcMatched) do
      Inc(J);
    if (J < I) or (M.Matched[J] = 0) then
      Continue;
    if (M.Matched[J] and IdcMatchedAttribute) = IdcMatchedAttribute then
    begin
      M.Matched[I] := 0;
      Continue;
    end;
    if not M.IsSelector then
    begin
      T := FFrames[Top].ComplexType;
      if (FFrames[Top].SimpleType = nil) and ((T = nil) or (T.ContentType <> xctSimple)) then
        IdcError('cvc-id.3', 'A field of identity constraint ''' + LandrixXmlEscapeForMessage(M.Constraint.Name,
          MaxInt) + ''' matched element ''' + LandrixXmlEscapeForMessage(M.Store.ElementName, MaxInt) +
          ''', but this element does not have a simple type.', M.Constraint);
      { as Xerces (KeyMatchesNillable): a key field matching an element of
        a nillable declaration, nilled or not }
      if (M.Constraint.Kind = xikKey) and (FFrames[Top].Decl <> nil) and FFrames[Top].Decl.Nillable then
        IdcError('cvc-identity-constraint.4.2.3', 'Element "' + LandrixXmlEscapeForMessage(M.Store.ElementName,
          MaxInt) + '" has the key "' + LandrixXmlEscapeForMessage(M.Constraint.Name, MaxInt) +
          '" which matches an element which has nillable set to true.', M.Constraint);
      if FFrames[Top].ValueKnown then
        FieldMatched(M, FFrames[Top].ValueKey, FFrames[Top].ValueText)
      else
        FieldMatched(M, '', 'null');
    end;
    M.Matched[I] := 0;
  end;
end;

function IsMatched(M: TIdcMatcher): Boolean;
var
  I: Integer;
begin
  for I := 0 to Integer(Length(M.Paths)) - 1 do
    if ((M.Matched[I] and IdcMatched) = IdcMatched) and
      ((M.Matched[I] and IdcMatchedDescendantPrevious) <> IdcMatchedDescendantPrevious) and
      ((M.NoMatchDepth[I] = 0) or ((M.Matched[I] and IdcMatchedDescendant) = IdcMatchedDescendant)) then
    begin
      Result := True;
      Exit;
    end;
  Result := False;
end;

{ Selector.Matcher.startElement: a selected element starts the value
  scope and activates the fields. }
procedure TLandrixXmlXsdValidator.SelectorStart(Matcher: TObject; const NamespaceUri, LocalName: TLandrixXmlUtf8);
var
  M, F: TIdcMatcher;
  I: Integer;
begin
  M := TIdcMatcher(Matcher);
  MatcherStart(M, NamespaceUri, LocalName);
  Inc(M.ElementDepth);
  if not IsMatched(M) then
    Exit;
  M.MatchedDepth := M.ElementDepth;
  M.Store.StartValueScope;
  for I := 0 to Integer(Length(M.Constraint.Fields)) - 1 do
  begin
    F := TIdcMatcher.Create(M.Constraint.Fields[I]);
    FMatchers.Add(F);
    F.Constraint := M.Constraint;
    F.Field := I;
    F.Store := M.Store;
    MatcherStart(F, NamespaceUri, LocalName);
  end;
end;

procedure TLandrixXmlXsdValidator.SelectorEnd(Matcher: TObject);
var
  M: TIdcMatcher;
begin
  M := TIdcMatcher(Matcher);
  MatcherEnd(M);
  if M.ElementDepth = M.MatchedDepth then
  begin
    M.MatchedDepth := -1;
    EndValueScope(M.Store);
  end;
  Dec(M.ElementDepth);
end;

{ ValueStoreBase.addValue: a field's value; a complete tuple is checked
  against the tuples so far (null values never compare equal) and kept. }
procedure TLandrixXmlXsdValidator.FieldMatched(Matcher: TObject; const Key, Text: TLandrixXmlUtf8);
var
  M: TIdcMatcher;
  S: TIdcStore;
  C: TLandrixXmlXsdIdentityConstraint;
  I: Integer;
  TupleKey, TupleText: TLandrixXmlUtf8;
  HasNull: Boolean;
begin
  M := TIdcMatcher(Matcher);
  S := M.Store;
  C := S.Constraint;
  if not M.MayMatch then
    IdcError('cvc-identity-constraint.3', 'Field "' + FieldText(C, M.Field) + '" of identity constraint "' +
      LandrixXmlEscapeForMessage(C.Name, MaxInt) + '" matches more than one value within the scope of its ' +
      'selector; fields must match unique values.', C)
  else
  begin
    Inc(S.ValuesCount);
    S.HasValue := True;
  end;
  M.MayMatch := False;
  S.LocalKeys[M.Field] := Key;
  S.LocalTexts[M.Field] := Text;
  if S.ValuesCount <> S.FieldCount then
    Exit;
  TupleKey := '';
  TupleText := '';
  HasNull := False;
  for I := 0 to S.FieldCount - 1 do
  begin
    if I > 0 then
    begin
      TupleKey := TupleKey + #9;
      TupleText := TupleText + ',';
    end;
    TupleKey := TupleKey + S.LocalKeys[I];
    TupleText := TupleText + S.LocalTexts[I];
    if S.LocalKeys[I] = '' then
      HasNull := True;
  end;
  if (C.Kind <> xikKeyRef) and not HasNull and (S.Tuples.Find('', TupleKey) <> nil) then
  begin
    if C.Kind = xikKey then
      IdcError('cvc-identity-constraint.4.2.2', 'Duplicate key value [' + LandrixXmlEscapeForMessage(TupleText,
        MaxInt) + '] declared for identity constraint "' + LandrixXmlEscapeForMessage(C.Name, MaxInt) +
        '" of element "' + LandrixXmlEscapeForMessage(S.ElementName, MaxInt) + '".', C)
    else
      IdcError('cvc-identity-constraint.4.1', 'Duplicate unique value [' + LandrixXmlEscapeForMessage(TupleText,
        MaxInt) + '] declared for identity constraint "' + LandrixXmlEscapeForMessage(C.Name, MaxInt) +
        '" of element "' + LandrixXmlEscapeForMessage(S.ElementName, MaxInt) + '".', C);
  end;
  S.AddTuple(TupleKey, TupleText);
end;

{ ValueStoreBase.endValueScope: the selected element ends. }
procedure TLandrixXmlXsdValidator.EndValueScope(Store: TObject);
var
  S: TIdcStore;
  C: TLandrixXmlXsdIdentityConstraint;
begin
  S := TIdcStore(Store);
  C := S.Constraint;
  if C.Kind <> xikKey then
    Exit;
  if S.ValuesCount = 0 then
    IdcError('cvc-identity-constraint.4.2.1.a', 'Element "' + LandrixXmlEscapeForMessage(S.ElementName, MaxInt) +
      '" has no value for the key "' + LandrixXmlEscapeForMessage(C.Name, MaxInt) + '".', C)
  else if S.ValuesCount <> S.FieldCount then
    IdcError('cvc-identity-constraint.4.2.1.b', 'Not enough values specified for <key name="' +
      LandrixXmlEscapeForMessage(C.Name, MaxInt) + '"> identity constraint specified for element "' +
      LandrixXmlEscapeForMessage(S.ElementName, MaxInt) + '".', C);
end;

{ KeyRefValueStore.endDocumentFragment: the first tuple not in the key's
  table in scope. }
procedure TLandrixXmlXsdValidator.CheckKeyRef(Store: TObject);
var
  S, K: TIdcStore;
  C: TLandrixXmlXsdIdentityConstraint;
  I: Integer;
begin
  S := TIdcStore(Store);
  C := S.Constraint;
  K := TIdcMap(FGlobal).Find(C.Refer);
  if K = nil then
  begin
    IdcError('KeyRefOutOfScope', 'Identity Constraint error:  identity constraint "' +
      LandrixXmlEscapeForMessage(C.Name, MaxInt) + '" has a keyref which refers to a key or unique that is ' +
      'out of scope.', C);
    Exit;
  end;
  for I := 0 to S.TupleCount - 1 do
    if K.Tuples.Find('', S.TupleKeys[I]) = nil then
    begin
      IdcError('cvc-identity-constraint.4.3', 'Key ''' + LandrixXmlEscapeForMessage(C.Name, MaxInt) +
        ''' with value ''' + LandrixXmlEscapeForMessage(S.TupleTexts[I], MaxInt) +
        ''' not found for identity constraint of element ''' + LandrixXmlEscapeForMessage(S.ElementName, MaxInt) +
        '''.', C);
      Exit;
    end;
end;

{ After the start tag of the element at the top of the stack (attributes
  checked and defaults added): a new map of the keys in scope, the
  selectors of the element's constraints, then every active matcher. }
procedure TLandrixXmlXsdValidator.IdentityStart(Line, Column: Integer);
var
  I, Count, Top: Integer;
  Decl: TLandrixXmlXsdElementDecl;
  M: TIdcMatcher;
  Map: TIdcMap;
begin
  Top := FDepth - 1;
  FIdcLine := Line;
  FIdcColumn := Column;
  { ValueStoreCache.startElement }
  if TIdcMap(FGlobal).Constraints.Count > 0 then
  begin
    Map := TIdcMap.Create;
    Map.Assign(TIdcMap(FGlobal));
    FMapStack.Add(Map);
  end
  else
    FMapStack.Add(nil);
  TIdcMap(FGlobal).Clear;
  if FContextCount = Length(FContexts) then
    SetLength(FContexts, 2 * FContextCount + 8);
  FContexts[FContextCount] := Integer(FMatchers.Count);
  Inc(FContextCount);
  Decl := FFrames[Top].Decl;
  if Decl <> nil then
    for I := 0 to Decl.ConstraintCount - 1 do
    begin
      M := TIdcMatcher.Create(Decl.Constraints[I].Selector);
      FMatchers.Add(M);
      M.IsSelector := True;
      M.Constraint := Decl.Constraints[I];
      M.Store := TIdcStore(StoreFor(M.Constraint, Top));
      M.InitialDepth := Top;
    end;
  Count := Integer(FMatchers.Count);
  for I := 0 to Count - 1 do
  begin
    M := TIdcMatcher(FMatchers[I]);
    if M.IsSelector then
      SelectorStart(M, FFrames[Top].NamespaceUri, FFrames[Top].LocalName)
    else
      MatcherStart(M, FFrames[Top].NamespaceUri, FFrames[Top].LocalName);
  end;
end;

{ Before the element at the top of the stack is removed: every active
  matcher, then the tables of this element's keys and uniques move into
  the map in scope, its keyrefs are checked, and the map is merged with
  the one of the preceding siblings. }
procedure TLandrixXmlXsdValidator.IdentityEnd(Line, Column: Integer);
var
  I, OldCount, NewCount: Integer;
  M: TIdcMatcher;
  Global, Old: TIdcMap;
  Current, OldStore: TIdcStore;
begin
  FIdcLine := Line;
  FIdcColumn := Column;
  Global := TIdcMap(FGlobal);
  OldCount := Integer(FMatchers.Count);
  for I := OldCount - 1 downto 0 do
  begin
    M := TIdcMatcher(FMatchers[I]);
    if M.IsSelector then
      SelectorEnd(M)
    else
      MatcherEnd(M);
  end;
  Dec(FContextCount);
  NewCount := FContexts[FContextCount];
  { ValueStoreCache.transplant }
  for I := OldCount - 1 downto NewCount do
  begin
    M := TIdcMatcher(FMatchers[I]);
    if not M.IsSelector or (M.Constraint.Kind = xikKeyRef) then
      Continue;
    Current := Global.Find(M.Constraint);
    if Current <> nil then
      Current.Append(M.Store)
    else
      Global.Put(M.Constraint, M.Store);
  end;
  for I := OldCount - 1 downto NewCount do
  begin
    M := TIdcMatcher(FMatchers[I]);
    if M.IsSelector and (M.Constraint.Kind = xikKeyRef) and M.Store.HasValue then
      CheckKeyRef(M.Store);
  end;
  for I := OldCount - 1 downto NewCount do
    FMatchers.Delete(I);
  { ValueStoreCache.endElement }
  I := Integer(FMapStack.Count) - 1;
  Old := TIdcMap(FMapStack[I]);
  FMapStack.OwnsObjects := False;
  try
    FMapStack.Delete(I);
  finally
    FMapStack.OwnsObjects := True;
  end;
  if Old = nil then
    Exit;
  try
    for I := 0 to Integer(Old.Constraints.Count) - 1 do
    begin
      OldStore := TIdcStore(Old.Stores[I]);
      Current := Global.Find(TLandrixXmlXsdIdentityConstraint(Old.Constraints[I]));
      if Current = nil then
        Global.Put(TLandrixXmlXsdIdentityConstraint(Old.Constraints[I]), OldStore)
      else if Current <> OldStore then
        Current.Append(OldStore);
    end;
  finally
    Old.Free;
  end;
end;

{ --------------------------------------------------------------------- }

constructor TLandrixXmlXsdValidator.Create(Schema: TLandrixXmlXsdSchemaSet);
begin
  inherited Create;
  if Schema = nil then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'A validator needs a schema');
  FSchema := Schema;
  FErrors := TObjectList.Create(True);
  FStates := TObjectList.Create(True);
  FIds := TLandrixXmlXsdNameMap.Create;
  FExpected := TList.Create;
  FMaxErrors := 1000;
  FValueContext := TValueContext.Create;
  FIdType := LandrixXmlXsdBuiltinType('ID');
  FIdRefType := LandrixXmlXsdBuiltinType('IDREF');
  FQNameType := LandrixXmlXsdBuiltinType('QName');
  FBooleanType := LandrixXmlXsdBuiltinType('boolean');
  FStores := TObjectList.Create(True);
  FStoreIndex := TLandrixXmlXsdNameMap.Create;
  FMatchers := TObjectList.Create(True);
  FGlobal := TIdcMap.Create;
  FMapStack := TObjectList.Create(True);
end;

destructor TLandrixXmlXsdValidator.Destroy;
begin
  FErrors.Free;
  FStates.Free;
  FIds.Free;
  FExpected.Free;
  FMatchers.Free;
  FMapStack.Free;
  FGlobal.Free;
  FStoreIndex.Free;
  FStores.Free;
  FValueContext.Free;
  inherited Destroy;
end;

function TLandrixXmlXsdValidator.GetErrorCount: Integer;
begin
  Result := Integer(FErrors.Count);
end;

function TLandrixXmlXsdValidator.GetError(Index: Integer): TLandrixXmlXsdValidationError;
begin
  Result := TLandrixXmlXsdValidationError(FErrors[Index]);
end;

procedure TLandrixXmlXsdValidator.Reset;
begin
  FErrors.Clear;
  FTruncated := False;
  FDepth := 0;
  FIds.Free;
  FIds := TLandrixXmlXsdNameMap.Create;
  FIdRefs := nil;
  FIdRefCount := 0;
  FBuffer := '';
  FAppendBuffer := False;
  FMatchers.Clear;
  FContextCount := 0;
  FMapStack.Clear;
  TIdcMap(FGlobal).Clear;
  FStoreIndex.Free;
  FStoreIndex := TLandrixXmlXsdNameMap.Create;
  FStores.Clear;
end;

function TLandrixXmlXsdValidator.Stopped: Boolean;
begin
  Result := FTruncated;
end;

procedure TLandrixXmlXsdValidator.AddError(const Code, Message: string; Line, Column: Integer;
  const Path: TLandrixXmlUtf8; const SchemaFile: string; SchemaLine: Integer; Node: TLandrixXmlNode);
var
  E: TLandrixXmlXsdValidationError;
begin
  if FTruncated then
    Exit;
  if (FMaxErrors > 0) and (FErrors.Count >= FMaxErrors) then
  begin
    FTruncated := True;
    Exit;
  end;
  E := TLandrixXmlXsdValidationError.Create;
  E.FCode := Code;
  E.FMessage := Message;
  E.FLine := Line;
  E.FColumn := Column;
  E.FPath := Path;
  E.FSchemaFile := SchemaFile;
  E.FSchemaLine := SchemaLine;
  if FDepth > 0 then
    E.FNode := FFrames[FDepth - 1].Node;
  if Node <> nil then
    E.FNode := Node;
  FErrors.Add(E);
end;

function TLandrixXmlXsdValidator.CurrentPath: TLandrixXmlUtf8;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to FDepth - 1 do
    Result := Result + '/' + FFrames[I].PathStep;
end;

{ Counts the child in the current element and gives its path step. }
function TLandrixXmlXsdValidator.ChildPathStep(const NamespaceUri, LocalName,
  Name: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I, N, P: Integer;
begin
  if FDepth = 0 then
  begin
    Result := Name;
    Exit;
  end;
  N := 0;
  P := FDepth - 1;
  for I := 0 to FFrames[P].ChildKinds - 1 do
    if (FFrames[P].Children[I].LocalName = LocalName) and (FFrames[P].Children[I].NamespaceUri = NamespaceUri) then
    begin
      Inc(FFrames[P].Children[I].Count);
      N := FFrames[P].Children[I].Count;
      Break;
    end;
  if N = 0 then
  begin
    if FFrames[P].ChildKinds = Length(FFrames[P].Children) then
      SetLength(FFrames[P].Children, 2 * FFrames[P].ChildKinds + 4);
    I := FFrames[P].ChildKinds;
    FFrames[P].Children[I].NamespaceUri := NamespaceUri;
    FFrames[P].Children[I].LocalName := LocalName;
    FFrames[P].Children[I].Count := 1;
    Inc(FFrames[P].ChildKinds);
    N := 1;
  end;
  Result := Name + '[' + LandrixXmlStringToUtf8(IntToStr(N)) + ']';
end;

procedure TLandrixXmlXsdValidator.Report(const Code, Message: string; Line, Column: Integer;
  Component: TLandrixXmlXsdComponent);
begin
  if Component <> nil then
    AddError(Code, Message, Line, Column, CurrentPath, Component.SchemaFile, Component.SchemaLine, nil)
  else
    AddError(Code, Message, Line, Column, CurrentPath, '', 0, nil);
end;

function TLandrixXmlXsdValidator.NewState: TLandrixXmlXsdContentState;
begin
  { one content state per depth, reused }
  while FStates.Count < FDepth + 1 do
    FStates.Add(TLandrixXmlXsdContentState.Create);
  Result := TLandrixXmlXsdContentState(FStates[FDepth]);
end;

procedure TLandrixXmlXsdValidator.ClearAttributes;
begin
  FAttrCount := 0;
end;

procedure TLandrixXmlXsdValidator.AddAttribute(const NamespaceUri, LocalName, Name, Value: TLandrixXmlUtf8);
begin
  if FAttrCount = Length(FAttrs) then
    SetLength(FAttrs, 2 * FAttrCount + 8);
  FAttrs[FAttrCount].NamespaceUri := NamespaceUri;
  FAttrs[FAttrCount].LocalName := LocalName;
  FAttrs[FAttrCount].Name := Name;
  FAttrs[FAttrCount].Value := Value;
  Inc(FAttrCount);
end;

{ ID and IDREF values (also of union members). }
{ False for a repeated ID, which Xerces counts as an invalid value. }
function TLandrixXmlXsdValidator.CheckIdValue(T: TLandrixXmlXsdSimpleType;
  const Value: TLandrixXmlXsdValue; Line, Column: Integer): Boolean;
var
  Member: TLandrixXmlXsdSimpleType;
  I: Integer;
begin
  if Value.Variety = xsvList then
  begin
    { as Xerces: the items from the last one, up to a repeated ID }
    Result := True;
    for I := Integer(Length(Value.Items)) - 1 downto 0 do
      if not CheckIdItem(Value.Items[I].MemberType, Value.Items[I].Text, Line, Column) then
      begin
        Result := False;
        Exit;
      end;
    Exit;
  end;
  Member := Value.MemberType;
  if Member = nil then
    Member := T;
  Result := CheckIdItem(Member, Value.Text, Line, Column);
end;

function TLandrixXmlXsdValidator.CheckIdItem(Member: TLandrixXmlXsdSimpleType; const Text: TLandrixXmlUtf8;
  Line, Column: Integer): Boolean;
begin
  Result := True;
  if Member.IsDerivedFrom(FIdType) then
  begin
    if not FIds.Add('', Text, Member) then
    begin
      AddError('cvc-id.2', 'There are multiple occurrences of ID value ' + Q(Text) + '.', Line, Column,
        CurrentPath, '', 0, nil);
      Result := False;
    end;
  end
  else if Member.IsDerivedFrom(FIdRefType) then
  begin
    if FIdRefCount = Length(FIdRefs) then
      SetLength(FIdRefs, 2 * FIdRefCount + 8);
    FIdRefs[FIdRefCount] := Text;
    Inc(FIdRefCount);
  end;
end;

{ The xsi attributes every element may have. Xerces deviation: schA1,
  ctL021, attgD034, particlesB013, targetNS00101m1_p, ST_targetNS00101m2_p.
  The location hints are allowed but never read (the schema is the one
  given, as a preloaded schema in Xerces), so an xsi:type naming a type
  of a hinted schema cannot be resolved. }
function IsXsiBuiltin(const A: TLandrixXmlXsdEventAttribute): Boolean;
begin
  Result := (A.NamespaceUri = LandrixXmlXsiNamespace) and ((A.LocalName = 'type') or (A.LocalName = 'nil') or
    (A.LocalName = 'schemaLocation') or (A.LocalName = 'noNamespaceSchemaLocation'));
end;

{ S without leading and trailing XML white space }
function TrimSpace(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  First, Last: Integer;
begin
  First := 1;
  Last := Integer(Length(S));
  while (First <= Last) and (S[First] in [#9, #10, #13, ' ']) do
    Inc(First);
  while (Last >= First) and (S[Last] in [#9, #10, #13, ' ']) do
    Dec(Last);
  Result := Copy(S, First, Last - First + 1);
end;

{ the value of the attribute xsi:LocalName of the current element }
function TLandrixXmlXsdValidator.FindXsi(const LocalName: TLandrixXmlUtf8; out Value: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  for I := 0 to FAttrCount - 1 do
    if (FAttrs[I].NamespaceUri = LandrixXmlXsiNamespace) and (FAttrs[I].LocalName = LocalName) then
    begin
      Value := FAttrs[I].Value;
      Result := True;
      Exit;
    end;
  Value := '';
  Result := False;
end;

{ Xerces' getAndCheckXsiType: the type named by xsi:type replaces CT or
  ST if it can be found; it must be validly derived from the declared
  type without the derivations the declaration and its type block }
procedure TLandrixXmlXsdValidator.ApplyXsiType(const Text, Name: TLandrixXmlUtf8; Decl: TLandrixXmlXsdElementDecl;
  var CT: TLandrixXmlXsdComplexType; var ST: TLandrixXmlXsdSimpleType; Line, Column: Integer);
var
  Value: TLandrixXmlXsdValue;
  Error: TLandrixXmlXsdError;
  NewCT: TLandrixXmlXsdComplexType;
  NewST: TLandrixXmlXsdSimpleType;
  Block: TLandrixXmlXsdDerivations;
  TypeName: string;
begin
  if not FQNameType.Validate(Text, FValueContext, Value, Error) then
  begin
    Report(Error.Code, Error.Message, Line, Column, Decl);
    Report('cvc-elt.4.1', 'The value ' + Q(Text) + ' of attribute ''' + LandrixXmlXsiNamespace + ',type'' of element ' +
      Q(Name) + ' is not a valid QName.', Line, Column, Decl);
    Exit;
  end;
  NewCT := nil;
  NewST := nil;
  if Value.NamespaceUri = LandrixXmlXsdNamespace then
  begin
    if Value.LocalName = 'anyType' then
      NewCT := FSchema.AnyType
    else
      NewST := LandrixXmlXsdBuiltinType(Value.LocalName);
    if (NewCT = nil) and (NewST = nil) and ((Value.LocalName = 'duration') or (Value.LocalName = 'NOTATION') or
      (Value.LocalName = 'ENTITY') or (Value.LocalName = 'ENTITIES')) then
    begin
      Report('unsupported', 'xsi:type ' + Q(Text) + ' names a type that is not supported (element ' + Q(Name) + ').',
        Line, Column, Decl);
      Exit;
    end;
  end;
  if (NewCT = nil) and (NewST = nil) then
  begin
    NewCT := FSchema.FindComplexType(Value.NamespaceUri, Value.LocalName);
    if NewCT = nil then
      NewST := FSchema.FindSimpleType(Value.NamespaceUri, Value.LocalName);
  end;
  if (NewCT = nil) and (NewST = nil) then
  begin
    Report('cvc-elt.4.2', 'Cannot resolve ' + Q(Text) + ' to a type definition for element ' + Q(Name) + '.', Line,
      Column, Decl);
    Exit;
  end;
  { without a declaration there is no type to derive from }
  if Decl <> nil then
  begin
    Block := Decl.Block;
    if CT <> nil then
      Block := Block + CT.Block;
    if not FSchema.TypeDerivationOk(NewST, NewCT, ST, CT, Block) then
    begin
      if CT <> nil then
        TypeName := LandrixXmlEscapeForMessage(CT.DisplayName, MaxInt)
      else
        TypeName := ST.DisplayName;
      Report('cvc-elt.4.3', 'Type ' + Q(Text) + ' is not validly derived from the type definition, ''' + TypeName +
        ''', of element ' + Q(Name) + '.', Line, Column, Decl);
    end;
  end;
  CT := NewCT;
  ST := NewST;
end;

{ Xerces' ElementDefaultValidImmediate: Text (a default in canonical
  form) is valid for the simple type or the simple content, or the
  content is mixed and emptiable }
function TLandrixXmlXsdValidator.DefaultValidFor(CT: TLandrixXmlXsdComplexType; ST: TLandrixXmlXsdSimpleType;
  const Text: TLandrixXmlUtf8): Boolean;
var
  Value: TLandrixXmlXsdValue;
  Error: TLandrixXmlXsdError;
  Issues: TLandrixXmlXsdContentIssues;
  State: TLandrixXmlXsdContentState;
begin
  Issues := nil;
  if (ST = nil) and (CT.ContentType = xctSimple) then
    ST := CT.SimpleType;
  if ST <> nil then
    Result := ST.Validate(Text, FValueContext, Value, Error)
  else if CT.ContentType <> xctMixed then
    Result := False
  else if CT.Model = nil then
    Result := True
  else
  begin
    State := TLandrixXmlXsdContentState.Create;
    try
      State.Start(CT.Model);
      Issues := State.Finish;
      Result := Length(Issues) = 0;
    finally
      State.Free;
    end;
  end;
end;

{ The attributes of the element in F, in document order, then the missing
  required ones, as Xerces checks them. }
procedure TLandrixXmlXsdValidator.CheckAttributes(var F: TLandrixXmlXsdFrame; Line, Column: Integer);
var
  I, J: Integer;
  T: TLandrixXmlXsdComplexType;
  Use: TLandrixXmlXsdAttributeUse;
  Decl: TLandrixXmlXsdAttributeDecl;
  Value: TLandrixXmlXsdValue;
  Error: TLandrixXmlXsdError;
  Present: Boolean;
  Wildcard: TLandrixXmlXsdWildcard;
  Valid: Boolean;
  WildId, UseId: TLandrixXmlUtf8;
  XsiType: TLandrixXmlXsdSimpleType;
begin
  T := F.ComplexType;
  { the first attribute matched by the wildcard whose type is ID: a second
    one (cvc-complex-type.5.1) or an ID among the attribute uses
    (cvc-complex-type.5.2) is an error, checked as Xerces does }
  WildId := '';
  for I := 0 to FAttrCount - 1 do
  begin
    if IsXsiBuiltin(FAttrs[I]) then
    begin
      { as Xerces: xsi:type is a QName, xsi:nil a boolean; the location
        hints are not looked at }
      if FAttrs[I].LocalName = 'type' then
        XsiType := FQNameType
      else if FAttrs[I].LocalName = 'nil' then
        XsiType := FBooleanType
      else
        XsiType := nil;
      if XsiType <> nil then
      begin
        if XsiType.Validate(FAttrs[I].Value, FValueContext, Value, Error) then
        begin
          FAttrValid[I] := True;
          FAttrValues[I] := Value;
        end
        else
        begin
          Report(Error.Code, Error.Message, Line, Column, F.Decl);
          Report('cvc-attribute.3', 'The value ' + Q(FAttrs[I].Value) + ' of attribute ' + Q(FAttrs[I].Name) +
            ' on element ' + Q(F.Name) + ' is not valid with respect to its type, ''' + XsiType.DisplayName + '''.',
            Line, Column, F.Decl);
        end;
      end;
      Continue;
    end;
    if F.SimpleType <> nil then
    begin
      Report('cvc-type.3.1.1', 'Element ' + Q(F.Name) + ' is a simple type, so it cannot have attributes, ' +
        'excepting those whose namespace name is identical to ''http://www.w3.org/2001/XMLSchema-instance'' ' +
        'and whose [local name] is one of ''type'', ''nil'', ''schemaLocation'' or ''noNamespaceSchemaLocation''. ' +
        'However, the attribute, ' + Q(FAttrs[I].Name) + ' was found.', Line, Column, F.Decl);
      Continue;
    end;
    Use := T.FindAttribute(FAttrs[I].NamespaceUri, FAttrs[I].LocalName);
    Decl := nil;
    Wildcard := nil;
    if Use <> nil then
      Decl := Use.Decl
    else
    begin
      { no attribute use: the wildcard; a declaration if it asks for one }
      Wildcard := T.AttributeWildcard;
      if (Wildcard <> nil) and Wildcard.Allows(FAttrs[I].NamespaceUri) and
        (Wildcard.ProcessContents <> xpcSkip) then
        Decl := FSchema.FindAttribute(FAttrs[I].NamespaceUri, FAttrs[I].LocalName);
    end;
    if Decl = nil then
    begin
      if Wildcard = nil then
        Report('cvc-complex-type.3.2.2', 'Attribute ' + Q(FAttrs[I].Name) + ' is not allowed to appear in element ' +
          Q(F.Name) + '.', Line, Column, T)
      else if not Wildcard.Allows(FAttrs[I].NamespaceUri) or (Wildcard.ProcessContents = xpcStrict) then
        Report('cvc-complex-type.3.2.2', 'Attribute ' + Q(FAttrs[I].Name) + ' is not allowed to appear in element ' +
          Q(F.Name) + '.', Line, Column, Wildcard);
      Continue;
    end;
    if (Use = nil) and Decl.SimpleType.IsDerivedFrom(FIdType) then
    begin
      if WildId <> '' then
        Report('cvc-complex-type.5.1', 'In element ' + Q(F.Name) + ', attribute ' + Q(Decl.Name) +
          ' is a Wild ID. But there is already a Wild ID ' + Q(WildId) + '. There can be only one.', Line, Column,
          Decl)
      else
        WildId := Decl.Name;
    end;
    Valid := Decl.SimpleType.Validate(FAttrs[I].Value, FValueContext, Value, Error);
    if not Valid then
      Report(Error.Code, Error.Message, Line, Column, Decl)
    else
      Valid := CheckIdValue(Decl.SimpleType, Value, Line, Column);
    if not Valid then
    begin
      Report('cvc-attribute.3', 'The value ' + Q(FAttrs[I].Value) + ' of attribute ' + Q(FAttrs[I].Name) +
        ' on element ' + Q(F.Name) + ' is not valid with respect to its type, ''' +
        Decl.SimpleType.DisplayName + '''.', Line, Column, Decl);
      Continue;
    end;
    { the declaration's fixed value, then the use's own (Xerces' order) }
    if (Decl.ValueConstraint = xvcFixed) and (LandrixXmlXsdCompareValues(Value, Decl.ConstraintActual) <> 0) then
      Report('cvc-attribute.4', 'The value ' + Q(FAttrs[I].Value) + ' of attribute ' + Q(FAttrs[I].Name) +
        ' on element ' + Q(F.Name) + ' is not valid with respect to its fixed {value constraint}. ' +
        'The attribute must have a value of ' + Q(Decl.ConstraintValue) + '.', Line, Column, Decl);
    if (Use <> nil) and (Use.ValueConstraint = xvcFixed) and
      (LandrixXmlXsdCompareValues(Value, Use.ConstraintActual) <> 0) then
      Report('cvc-complex-type.3.1', 'Value ' + Q(FAttrs[I].Value) + ' of attribute ' + Q(FAttrs[I].Name) +
        ' of element ' + Q(F.Name) + ' is not valid with respect to the corresponding attribute use. Attribute ' +
        Q(FAttrs[I].Name) + ' has a fixed value of ' + Q(Use.ConstraintValue) + '.', Line, Column, Decl);
    FAttrValid[I] := True;
    FAttrValues[I] := Value;
  end;
  if T = nil then
    Exit;
  if WildId <> '' then
  begin
    UseId := '';
    for I := 0 to T.AttributeCount - 1 do
      if (UseId = '') and T.Attributes[I].Decl.SimpleType.IsDerivedFrom(FIdType) then
        UseId := T.Attributes[I].Decl.Name;
    if UseId <> '' then
      Report('cvc-complex-type.5.2', 'In element ' + Q(F.Name) + ', attribute ' + Q(WildId) +
        ' is a Wild ID. But there is already an attribute ' + Q(UseId) + ' derived from ID among the ' +
        '{attribute uses}.', Line, Column, T);
  end;
  for I := 0 to T.AttributeCount - 1 do
  begin
    Use := T.Attributes[I];
    if not Use.Required then
      Continue;
    Present := False;
    for J := 0 to FAttrCount - 1 do
      if (FAttrs[J].LocalName = Use.Decl.Name) and (FAttrs[J].NamespaceUri = Use.Decl.NamespaceUri) then
      begin
        Present := True;
        Break;
      end;
    if not Present then
    begin
      if Use.Decl.NamespaceUri = '' then
        Report('cvc-complex-type.4', 'Attribute ' + Q(Use.Decl.Name) + ' must appear on element ' + Q(F.Name) + '.',
          Line, Column, Use.Decl)
      else
        Report('cvc-complex-type.4', 'Attribute ' + Q(Use.Decl.Name) + ' belonging to namespace ' +
          Q(Use.Decl.NamespaceUri) + ', must appear on element ' + Q(F.Name) + '.', Line, Column, Use.Decl);
    end;
  end;
end;

{ Absent attributes with a default or fixed value, appended after the
  given ones for the identity constraints (Xerces adds them to the
  attributes its matchers see). }
procedure TLandrixXmlXsdValidator.AddDefaultAttributes(T: TLandrixXmlXsdComplexType);
var
  I, J: Integer;
  Use: TLandrixXmlXsdAttributeUse;
  S: TLandrixXmlUtf8;
  Present: Boolean;
  Value: TLandrixXmlXsdValue;
begin
  if T = nil then
    Exit;
  for I := 0 to T.AttributeCount - 1 do
  begin
    Use := T.Attributes[I];
    if Use.ValueConstraint <> xvcNone then
    begin
      S := Use.ConstraintValue;
      Value := Use.ConstraintActual;
    end
    else if Use.Decl.ValueConstraint <> xvcNone then
    begin
      S := Use.Decl.ConstraintValue;
      Value := Use.Decl.ConstraintActual;
    end
    else
      Continue;
    Present := False;
    for J := 0 to FAttrCount - 1 do
      if (FAttrs[J].LocalName = Use.Decl.Name) and (FAttrs[J].NamespaceUri = Use.Decl.NamespaceUri) then
      begin
        Present := True;
        Break;
      end;
    if Present then
      Continue;
    AddAttribute(Use.Decl.NamespaceUri, Use.Decl.Name, Use.Decl.Name, S);
    if Length(FAttrValid) < FAttrCount then
    begin
      SetLength(FAttrValid, FAttrCount);
      SetLength(FAttrValues, FAttrCount);
    end;
    { as Xerces: the value the schema loader validated, in the namespace
      context of the schema (identity constraints use it).
      Xerces deviation: idZ012. A default or fixed value is not registered
      as an ID or IDREF }
    FAttrValid[FAttrCount - 1] := True;
    FAttrValues[FAttrCount - 1] := Value;
  end;
end;

procedure TLandrixXmlXsdValidator.StartElement(const NamespaceUri, LocalName, Name: TLandrixXmlUtf8;
  Line, Column: Integer; Node: TLandrixXmlNode);
var
  Parent, I: Integer;
  Mode: TLandrixXmlXsdFrameMode;
  Decl: TLandrixXmlXsdElementDecl;
  Particle: TLandrixXmlXsdParticle;
  Issue: TLandrixXmlXsdContentIssue;
  Code, Message: string;
  Wildcard: TLandrixXmlXsdWildcard;
  Step: TLandrixXmlUtf8;
  CT: TLandrixXmlXsdComplexType;
  ST: TLandrixXmlXsdSimpleType;
  HasXsiType: Boolean;
  XsiType, XsiNil, S: TLandrixXmlUtf8;
begin
  if Stopped then
    Exit;
  TValueContext(FValueContext).Node := Node;
  HasXsiType := FindXsi('type', XsiType);
  Parent := FDepth - 1;
  Mode := xfmValidate;
  Decl := nil;
  Wildcard := nil;
  Step := ChildPathStep(NamespaceUri, LocalName, Name);
  if (Parent >= 0) and (FFrames[Parent].Mode = xfmSkip) then
    Mode := xfmSkip
  else
  begin
    if Parent >= 0 then
    begin
      FFrames[Parent].HasChild := True;
      if FFrames[Parent].State <> nil then
      begin
        Particle := FFrames[Parent].State.Step(NamespaceUri, LocalName, Issue);
        if Issue.Kind <> xciNone then
        begin
          FFrames[Parent].State.Expected(FExpected);
          LandrixXmlXsdContentIssueText(Issue, Name, NamespaceUri, LocalName, FFrames[Parent].Name, FExpected,
            False, Code, Message);
          AddError(Code, Message, Line, Column, CurrentPath + '/' + Step, FFrames[Parent].ComplexType.SchemaFile,
            FFrames[Parent].ComplexType.SchemaLine, Node);
        end;
        if Particle <> nil then
        begin
          if Particle.Kind = xpkElement then
            Decl := TLandrixXmlXsdElementDecl(Particle.Decl)
          else
          begin
            Wildcard := TLandrixXmlXsdWildcard(Particle.Decl);
            if Wildcard.ProcessContents = xpcSkip then
              Mode := xfmSkip;
          end;
        end;
      end;
    end;
    { no declaration from the content model: a global one, else anyType }
    if (Mode = xfmValidate) and (Decl = nil) then
    begin
      Decl := FSchema.FindElement(NamespaceUri, LocalName);
      { as Xerces: an xsi:type gives the element a type, so there is no
        error and no lax assessment }
      if (Decl = nil) and not HasXsiType then
      begin
        if Parent < 0 then
          AddError('cvc-elt.1.a', 'Cannot find the declaration of element ' + Q(Name) + '.', Line, Column,
            '/' + Step, '', 0, Node)
        else if (Wildcard <> nil) and (Wildcard.ProcessContents = xpcStrict) then
          AddError('cvc-complex-type.2.4.c', 'The matching wildcard is strict, but no declaration can be ' +
            'found for element ' + Q(Name) + '.', Line, Column, CurrentPath + '/' + Step,
            Wildcard.SchemaFile, Wildcard.SchemaLine, Node);
        Mode := xfmLax;
      end;
    end;
  end;
  { Xerces empties its text buffer for every element it looks at }
  if (Parent < 0) or (FFrames[Parent].Mode <> xfmSkip) then
    FBuffer := '';
  { the new frame }
  if FDepth = Length(FFrames) then
    SetLength(FFrames, 2 * FDepth + 8);
  FFrames[FDepth].Mode := Mode;
  FFrames[FDepth].Decl := Decl;
  FFrames[FDepth].Name := Name;
  FFrames[FDepth].NamespaceUri := NamespaceUri;
  FFrames[FDepth].LocalName := LocalName;
  FFrames[FDepth].PathStep := Step;
  FFrames[FDepth].HasChild := False;
  FFrames[FDepth].HasText := False;
  FFrames[FDepth].HasNonSpaceText := False;
  FFrames[FDepth].Nilled := False;
  FFrames[FDepth].ChildKinds := 0;
  FFrames[FDepth].State := nil;
  FFrames[FDepth].ComplexType := nil;
  FFrames[FDepth].SimpleType := nil;
  FFrames[FDepth].Node := Node;
  FFrames[FDepth].ValueKnown := False;
  Inc(FDepth);
  if Mode = xfmSkip then
    Exit;
  if Decl <> nil then
  begin
    CT := Decl.ComplexType;
    ST := Decl.SimpleType;
  end
  else
  begin
    CT := FSchema.AnyType;
    ST := nil;
  end;
  if HasXsiType and (Mode = xfmValidate) then
    ApplyXsiType(XsiType, Name, Decl, CT, ST, Line, Column);
  FFrames[FDepth - 1].ComplexType := CT;
  FFrames[FDepth - 1].SimpleType := ST;
  FAppendBuffer := ((Decl <> nil) and (Decl.ValueConstraint = xvcFixed)) or (ST <> nil) or
    (CT.ContentType = xctSimple);
  if Length(FAttrValid) < FAttrCount then
  begin
    SetLength(FAttrValid, FAttrCount);
    SetLength(FAttrValues, FAttrCount);
  end;
  for I := 0 to FAttrCount - 1 do
    FAttrValid[I] := False;
  if (CT <> nil) and CT.Abstract then
    Report('cvc-type.2', 'The type definition cannot be abstract for element ' +
      LandrixXmlEscapeForMessage(Name, MaxInt) + '.', Line, Column, Decl);
  { Xerces' getXsiNil, only with a declaration }
  if (Decl <> nil) and FindXsi('nil', XsiNil) then
  begin
    if not Decl.Nillable then
      Report('cvc-elt.3.1', 'Attribute ''' + LandrixXmlXsiNamespace + ',nil'' must not appear on element ' + Q(Name) +
        ', because the {nillable} property of ' + Q(Name) + ' is false.', Line, Column, Decl)
    else
    begin
      S := TrimSpace(XsiNil);
      if (S = 'true') or (S = '1') then
      begin
        if Decl.ValueConstraint = xvcFixed then
          Report('cvc-elt.3.2.2', 'There must be no fixed {value constraint} for element ' + Q(Name) + ', because ''' +
            LandrixXmlXsiNamespace + ',nil'' is specified.', Line, Column, Decl);
        FFrames[FDepth - 1].Nilled := True;
      end;
    end;
  end;
  CheckAttributes(FFrames[FDepth - 1], Line, Column);
  if ST = nil then
    AddDefaultAttributes(CT);
  IdentityStart(Line, Column);
  if (CT <> nil) and (CT.Model <> nil) then
  begin
    FFrames[FDepth - 1].State := NewState;
    FFrames[FDepth - 1].State.Start(CT.Model);
  end;
end;

procedure TLandrixXmlXsdValidator.Text(const Value: TLandrixXmlUtf8; IsWhitespace: Boolean);
var
  I: Integer;
begin
  if Stopped or (FDepth = 0) or (Value = '') then
    Exit;
  I := FDepth - 1;
  if FFrames[I].Mode = xfmSkip then
    Exit;
  FFrames[I].HasText := True;
  if not IsWhitespace then
    FFrames[I].HasNonSpaceText := True;
  if FAppendBuffer then
    FBuffer := FBuffer + Value;
end;

procedure TLandrixXmlXsdValidator.EndElement(Line, Column: Integer);
var
  F: TLandrixXmlXsdFrame;
  T: TLandrixXmlXsdSimpleType;
  Decl: TLandrixXmlXsdElementDecl;
  Value: TLandrixXmlXsdValue;
  Error: TLandrixXmlXsdError;
  S: TLandrixXmlUtf8;
  Issues: TLandrixXmlXsdContentIssues;
  I: Integer;
  Code, Message: string;
  IsSimpleType, Valid, UseDefault, IsFixed, Nilled: Boolean;
  DefaultText: TLandrixXmlUtf8;
  TypeName: string;
begin
  Issues := nil;
  if Stopped or (FDepth = 0) then
    Exit;
  F := FFrames[FDepth - 1];
  if F.Mode <> xfmSkip then
  begin
    Decl := F.Decl;
    Nilled := F.Nilled;
    if Nilled and (F.HasChild or F.HasText) then
      Report('cvc-elt.3.2.1', 'Element ' + Q(F.Name) + ' cannot have character or element information [children], ' +
        'because ''' + LandrixXmlXsiNamespace + ',nil'' is specified.', Line, Column, Decl);
    { the value constraint applies to an element without any content }
    UseDefault := (Decl <> nil) and (Decl.ValueConstraint <> xvcNone) and not F.HasChild and not F.HasText and
      not Nilled;
    IsFixed := (Decl <> nil) and (Decl.ValueConstraint = xvcFixed) and not UseDefault and not Nilled;
    TValueContext(FValueContext).Node := F.Node;
    DefaultText := '';
    if UseDefault then
    begin
      { as Xerces: the canonical form of the value; with an xsi:type it
        must be a valid default for that type too }
      DefaultText := LandrixXmlXsdValueText(Decl.ConstraintActual);
      if ((F.SimpleType <> Decl.SimpleType) or (F.ComplexType <> Decl.ComplexType)) and
        not DefaultValidFor(F.ComplexType, F.SimpleType, DefaultText) then
      begin
        if F.SimpleType <> nil then
          TypeName := F.SimpleType.DisplayName
        else
          TypeName := LandrixXmlEscapeForMessage(F.ComplexType.DisplayName, MaxInt);
        Report('cvc-elt.5.1.1', '{value constraint} ' + Q(DefaultText) + ' of element ' + Q(F.Name) +
          ' is not a valid default value for type ''' + TypeName + '''.', Line, Column, Decl);
      end;
    end;
    T := F.SimpleType;
    IsSimpleType := T <> nil;
    if (T = nil) and (F.ComplexType.ContentType = xctSimple) then
      T := F.ComplexType.SimpleType;
    if (T <> nil) and Nilled then
    begin
      if F.HasChild and IsSimpleType then
        Report('cvc-type.3.1.2', 'Element ' + Q(F.Name) + ' is a simple type, so it must have no element ' +
          'information item [children].', Line, Column, F.Decl);
    end
    else if T <> nil then
    begin
      if F.HasChild then
      begin
        if IsSimpleType then
          Report('cvc-type.3.1.2', 'Element ' + Q(F.Name) + ' is a simple type, so it must have no element ' +
            'information item [children].', Line, Column, F.Decl)
        else
          Report('cvc-complex-type.2.2', 'Element ' + Q(F.Name) + ' must have no element [children], and the ' +
            'value must be valid.', Line, Column, F.ComplexType);
      end;
      if UseDefault then
        S := DefaultText
      else
        S := FBuffer;
      Valid := T.Validate(S, FValueContext, Value, Error);
      if not Valid then
        Report(Error.Code, Error.Message, Line, Column, F.Decl)
      else
        Valid := CheckIdValue(T, Value, Line, Column);
      if not Valid then
      begin
        if IsSimpleType then
          Report('cvc-type.3.1.3', 'The value ' + Q(S) + ' of element ' + Q(F.Name) + ' is not valid.', Line,
            Column, F.Decl)
        else
          Report('cvc-complex-type.2.2', 'Element ' + Q(F.Name) + ' must have no element [children], and the ' +
            'value must be valid.', Line, Column, F.ComplexType);
      end
      else
      begin
        FFrames[FDepth - 1].ValueKnown := True;
        FFrames[FDepth - 1].ValueKey := LandrixXmlXsdValueKey(Value);
        FFrames[FDepth - 1].ValueText := LandrixXmlXsdValueText(Value);
      end;
      { as Xerces: an applied default gives identity constraints the value
        the schema loader validated (in the schema's namespace context),
        whatever the check in the document's context found }
      if UseDefault then
      begin
        FFrames[FDepth - 1].ValueKnown := True;
        FFrames[FDepth - 1].ValueKey := LandrixXmlXsdValueKey(Decl.ConstraintActual);
        FFrames[FDepth - 1].ValueText := LandrixXmlXsdValueText(Decl.ConstraintActual);
      end;
      if IsFixed then
      begin
        if F.HasChild then
          Report('cvc-elt.5.2.2.1', 'Element ' + Q(F.Name) + ' must have no element information item [children].',
            Line, Column, Decl);
        if Valid and (LandrixXmlXsdCompareValues(Value, Decl.ConstraintActual) <> 0) then
          Report('cvc-elt.5.2.2.2.2', 'The value ' + Q(S) + ' of element ' + Q(F.Name) +
            ' does not match the {value constraint} value ' + Q(LandrixXmlXsdValueText(Decl.ConstraintActual)) + '.',
            Line, Column, Decl);
      end;
    end
    else if not Nilled then
    begin
      case F.ComplexType.ContentType of
        xctEmpty:
          if F.HasChild or F.HasText then
            Report('cvc-complex-type.2.1', 'Element ' + Q(F.Name) + ' must have no character or element ' +
              'information item [children], because the type''s content type is empty.', Line, Column, F.ComplexType);
        xctElementOnly:
          if F.HasNonSpaceText then
            Report('cvc-complex-type.2.3', 'Element ' + Q(F.Name) + ' cannot have character [children], because ' +
              'the type''s content type is element-only.', Line, Column, F.ComplexType);
      else
        { mixed: any text }
      end;
      if F.State <> nil then
      begin
        Issues := F.State.Finish;
        for I := 0 to Integer(Length(Issues)) - 1 do
        begin
          F.State.Expected(FExpected);
          LandrixXmlXsdContentIssueText(Issues[I], '', '', '', F.Name, FExpected, True, Code, Message);
          Report(Code, Message, Line, Column, F.ComplexType);
        end;
      end;
      if IsFixed then
      begin
        if F.HasChild then
          Report('cvc-elt.5.2.2.1', 'Element ' + Q(F.Name) + ' must have no element information item [children].',
            Line, Column, Decl);
        { mixed content: the text as it is must equal the fixed value }
        if (F.ComplexType.ContentType = xctMixed) and (FBuffer <> Decl.ConstraintValue) then
          Report('cvc-elt.5.2.2.2.1', 'The value ' + Q(FBuffer) + ' of element ' + Q(F.Name) +
            ' does not match the fixed {value constraint} value ' + Q(Decl.ConstraintValue) + '.', Line, Column,
            Decl);
      end;
    end;
    FAppendBuffer := False;
    IdentityEnd(Line, Column);
  end;
  Dec(FDepth);
end;

{ Java's String.hashCode of S over UTF-16 code units, spread as
  java.util.HashMap does (32 bits, unsigned). }
function JavaHash(const S: TLandrixXmlUtf8): Int64;
var
  H: Int64;
  P, N: Integer;
  C: Cardinal;
begin
  H := 0;
  P := 1;
  while P <= Length(S) do
  begin
    N := LandrixXmlDecodeUtf8(PAnsiChar(@S[P]), Length(S) - P + 1, C);
    if N = 0 then
    begin
      C := Ord(S[P]);
      N := 1;
    end;
    if C >= $10000 then
    begin
      H := (H * 31 + $D800 + ((C - $10000) shr 10)) and $FFFFFFFF;
      H := (H * 31 + $DC00 + ((C - $10000) and $3FF)) and $FFFFFFFF;
    end
    else
      H := (H * 31 + C) and $FFFFFFFF;
    Inc(P, N);
  end;
  Result := H xor (H shr 16);
end;

{ Sorts unique keys ascending (shell sort). }
procedure SortKeys(var Keys: array of Int64);
var
  Gap, I, J: Integer;
  K: Int64;
begin
  Gap := 1;
  while Gap < Integer(Length(Keys)) div 3 do
    Gap := 3 * Gap + 1;
  while Gap > 0 do
  begin
    for I := Gap to Integer(Length(Keys)) - 1 do
    begin
      K := Keys[I];
      J := I;
      while (J >= Gap) and (Keys[J - Gap] > K) do
      begin
        Keys[J] := Keys[J - Gap];
        Dec(J, Gap);
      end;
      Keys[J] := K;
    end;
    Gap := Gap div 3;
  end;
end;

{ Xerces collects the IDREFs without an ID in a java.util.HashSet and
  reports them in its order: by bucket, within a bucket in the order of
  their first reference. The table starts with 16 buckets and doubles
  when it holds more than three quarters of its size, or when a ninth
  entry lands in one bucket while it has fewer than 64 buckets (with 64
  or more, Java turns such a bucket into a tree, whose order is not
  reproduced here). }
procedure TLandrixXmlXsdValidator.EndDocument(Line, Column: Integer);
var
  I, J, Count, Capacity, B: Integer;
  Seen: TLandrixXmlXsdNameMap;
  Missing: TLandrixXmlUtf8Array;
  Keys, Hashes: array of Int64;
  Sizes: array of Integer;
begin
  if Stopped then
    Exit;
  Missing := nil;
  Keys := nil;
  Hashes := nil;
  Sizes := nil;
  Count := 0;
  Seen := TLandrixXmlXsdNameMap.Create;
  try
    for I := 0 to FIdRefCount - 1 do
      if (FIds.Find('', FIdRefs[I]) = nil) and Seen.Add('', FIdRefs[I], Self) then
      begin
        if Count = Length(Missing) then
          SetLength(Missing, 2 * Count + 8);
        Missing[Count] := FIdRefs[I];
        Inc(Count);
      end;
  finally
    Seen.Free;
  end;
  if Count = 0 then
    Exit;
  SetLength(Hashes, Count);
  for I := 0 to Count - 1 do
    Hashes[I] := JavaHash(Missing[I]);
  { insert them as java.util.HashMap.putVal does }
  Capacity := 16;
  SetLength(Sizes, Capacity);
  for I := 0 to Count - 1 do
  begin
    B := Integer(Hashes[I] and (Capacity - 1));
    Inc(Sizes[B]);
    if ((Sizes[B] > 8) and (Capacity < 64)) or (I + 1 > Capacity div 4 * 3) then
    begin
      { a full bucket (treeifyBin resizes) and the size threshold each
        double the table; both can happen for one entry }
      if (Sizes[B] > 8) and (Capacity < 64) then
        Capacity := Capacity * 2;
      if I + 1 > Capacity div 4 * 3 then
        Capacity := Capacity * 2;
      Sizes := nil;
      SetLength(Sizes, Capacity);
      for J := 0 to I do
        Inc(Sizes[Integer(Hashes[J] and (Capacity - 1))]);
    end;
  end;
  SetLength(Keys, Count);
  for I := 0 to Count - 1 do
    Keys[I] := (Hashes[I] and (Capacity - 1)) * Count + I;
  SortKeys(Keys);
  for I := 0 to Count - 1 do
    AddError('cvc-id.1', 'There is no ID/IDREF binding for IDREF ' + Q(Missing[Integer(Keys[I] mod Count)]) + '.', Line,
      Column, '', '', 0, nil);
end;

{ --- adapters ---------------------------------------------------------- }

function TLandrixXmlXsdValidator.ValidateFile(const FileName: string): Boolean;
var
  Reader: TLandrixXmlReader;
begin
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromFile(FileName);
    Result := ValidateReader(Reader);
  finally
    Reader.Free;
  end;
end;

function TLandrixXmlXsdValidator.ValidateReader(Reader: TLandrixXmlReader): Boolean;
var
  I, EndLine, EndColumn: Integer;
begin
  Reset;
  EndLine := 0;
  EndColumn := 0;
  TValueContext(FValueContext).Reader := Reader;
  while Reader.Read do
  begin
    case Reader.TokenType of
      xttStartElement:
        begin
          ClearAttributes;
          for I := 0 to Reader.AttributeCount - 1 do
            if not Reader.IsNamespaceDeclaration(I) then
              AddAttribute(Reader.AttributeNamespaceUriUtf8(I), Reader.AttributeLocalNameUtf8(I),
                Reader.AttributeNameUtf8(I), Reader.AttributeValueUtf8(I));
          StartElement(Reader.NamespaceUriUtf8, Reader.LocalNameUtf8, Reader.NameUtf8, Reader.TokenEndLine,
            Reader.TokenEndColumn, nil);
        end;
      xttEndElement:
        begin
          EndLine := Reader.TokenEndLine;
          EndColumn := Reader.TokenEndColumn;
          EndElement(EndLine, EndColumn);
        end;
      xttText:
        Text(Reader.ValueUtf8, Reader.IsWhitespace);
      xttCData:
        Text(Reader.ValueUtf8, IsSpaceText(Reader.ValueUtf8));
    else
      { comments, processing instructions, the document type }
    end;
    if Stopped then
      Break;
  end;
  EndDocument(EndLine, EndColumn);
  TValueContext(FValueContext).Reader := nil;
  Result := FErrors.Count = 0;
end;

function TLandrixXmlXsdValidator.ValidateDocument(Document: TLandrixXmlDocument): Boolean;
var
  Node, Next: TLandrixXmlNode;
  I: Integer;
  Root: TLandrixXmlNode;
begin
  Reset;
  TValueContext(FValueContext).Reader := nil;
  Root := Document.Root;
  Node := Root;
  while (Node <> nil) and not Stopped do
  begin
    case Node.NodeType of
      xntElement:
        begin
          ClearAttributes;
          for I := 0 to Node.AttributeCount - 1 do
            if not Node.IsNamespaceDeclaration(I) then
              AddAttribute(Node.AttributeNamespaceUriUtf8(I), Node.AttributeLocalNameUtf8(I),
                Node.AttributeNameUtf8(I), Node.AttributeValueUtf8(I));
          StartElement(Node.NamespaceUriUtf8, Node.LocalNameUtf8, Node.NameUtf8, Node.Line, Node.Column, Node);
          if Node.FirstChild <> nil then
          begin
            Node := Node.FirstChild;
            Continue;
          end;
          EndElement(Node.Line, Node.Column);
        end;
      xntText:
        Text(Node.ValueUtf8, IsSpaceText(Node.ValueUtf8));
      xntCData:
        Text(Node.ValueUtf8, IsSpaceText(Node.ValueUtf8));
    else
      { comments and processing instructions }
    end;
    { next node in document order, closing finished elements }
    if Node = Root then
      Break;
    Next := Node.NextSibling;
    while (Next = nil) and (Node <> Root) do
    begin
      Node := Node.Parent;
      EndElement(Node.Line, Node.Column);
      if Node = Root then
        Break;
      Next := Node.NextSibling;
    end;
    if Node = Root then
      Break;
    Node := Next;
  end;
  EndDocument(Root.Line, Root.Column);
  Result := FErrors.Count = 0;
end;

end.
