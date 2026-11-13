{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Schematron validation with a rule file compiled by tools/sch-compile.py
  (from ISO Schematron with XSLT 2 query binding, as the EN16931 and
  XRechnung rules are written). The rules run as the XSLT the KoSIT
  validator uses (SchXslt): every rule context is evaluated once per
  document; in document order each node is matched, per pattern, by the
  first rule (in schema order) whose context contains it; the asserts and
  reports of that rule are checked with the node as context item and as
  current(). The results come per pattern in schema order, inside a
  pattern in document order, as in the SVRL SchXslt writes.

  Global variables (lets of the schema and of patterns) are evaluated
  once, lazily, with the document node as context; the lets of a rule
  once per matched node. User functions are those of the rule file. A
  rule context is evaluated as //context per union branch (rooted ones
  as written, document-node() as /), which selects the nodes the XSLT
  match pattern matches; current() in a rule context is rejected when
  the rules are loaded. As in XSLT, a dynamic error in a predicate of the
  context only means that the node concerned does not match the rule.

  A dynamic error in an expression (an invalid cast, a type error) stops
  Saxon and with it the KoSIT validator: no result at all. Here it gives
  a result of kind xsrDynamicError and validation goes on (Incomplete is
  then True, and Valid is False); with AbortOnDynamicError the validation
  stops at the first one, as Saxon does.

  SaveSvrlToStream and SaveSvrlToFile write the last validation as SVRL in
  the layout of SchXslt (as the KoSIT validator reports EN16931 and
  XRechnung): per pattern svrl:active-pattern, then in document order
  svrl:fired-rule (context, id, role, flag of the rule) with its
  svrl:failed-assert and svrl:successful-report,
  and for later rules of the pattern that match the same node a comment
  and svrl:suppressed-rule. Locations as in the results; svrl:text is the
  message with white space normalized; no svrl:metadata. A dynamic error
  is an XML comment where it occurred (SVRL has no element for it).

  TLandrixXmlSchematronRules is immutable after loading and can be shared
  by validators in several threads; a validator is used by one thread. }

unit LandrixXmlSchematron;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  Classes,
  Contnrs,
  LandrixXmlBase,
  LandrixXmlDom,
  LandrixXmlXPathTree,
  LandrixXmlXsdTypes,
  LandrixXmlXPath,
  LandrixXmlXPathEval;

const
  LandrixXmlSchematronRulesNamespace = 'urn:landrix:schematron-rules';

type
  TLandrixXmlSchematronResultKind = (xsrFailedAssert, xsrSuccessfulReport, xsrDynamicError);

  { Internal, public only because Delphi 6 has no nested types. }
  TLandrixXmlSchematronPartKind = (xspText, xspValueOf, xspName);
  TLandrixXmlSchematronPart = record
    Kind: TLandrixXmlSchematronPartKind;
    Text: TLandrixXmlUtf8;
    Expression: TLandrixXmlXPathExpression;
  end;

  TLandrixXmlSchematronCheck = class
  public
    IsReport: Boolean;
    Id: TLandrixXmlUtf8;
    Flag: TLandrixXmlUtf8;
    Role: TLandrixXmlUtf8;
    TestText: TLandrixXmlUtf8;
    Test: TLandrixXmlXPathExpression;
    Parts: array of TLandrixXmlSchematronPart;
    SourceLine: string;
    destructor Destroy; override;
  end;

  TLandrixXmlSchematronRule = class
  public
    Id: TLandrixXmlUtf8;
    { as written in the rule set (SVRL svrl:fired-rule) }
    Flag: TLandrixXmlUtf8;
    Role: TLandrixXmlUtf8;
    ContextText: TLandrixXmlUtf8;
    Context: TLandrixXmlXPathExpression;
    LetSlots: array of Integer;
    Lets: array of TLandrixXmlXPathExpression;
    Checks: TObjectList;
    SourceLine: string;
    constructor Create;
    destructor Destroy; override;
  end;

  TLandrixXmlSchematronPattern = class
  public
    Id: TLandrixXmlUtf8;
    Rules: TObjectList;
    constructor Create;
    destructor Destroy; override;
  end;

  { A loaded rule file. }
  TLandrixXmlSchematronRules = class
  private
    FTitle: TLandrixXmlUtf8;
    FSource: TLandrixXmlUtf8;
    FSha256: TLandrixXmlUtf8;
    FContext: TLandrixXmlXPathStaticContext;
    FFunctionContexts: TObjectList;
    FGlobalSlots: array of Integer;
    FGlobals: TObjectList;
    FGlobalCount: Integer;
    FFunctions: TList;
    FOwnedFunctions: TObjectList;
    FPatterns: TObjectList;
    FExpressions: TObjectList;
    { embedded documents (document()): the URIs and their trees }
    FDocumentUris: TLandrixXmlUtf8Array;
    { the namespaces of the rule file, in order (for SVRL) }
    FNsPrefixes: TLandrixXmlUtf8Array;
    FNsUris: TLandrixXmlUtf8Array;
    FDocuments: TObjectList;
    procedure Clear;
    procedure Load(Document: TLandrixXmlDocument);
    function Compile(const Text: TLandrixXmlUtf8; Context: TLandrixXmlXPathStaticContext;
      const Where: string): TLandrixXmlXPathExpression;
    function GetPatternCount: Integer;
    function GetPattern(Index: Integer): TLandrixXmlSchematronPattern;
  public
    constructor Create;
    destructor Destroy; override;
    { Raises ELandrixXmlError: xecSchema for an invalid rule file,
      xecXPath (ELandrixXmlXPathError) for an expression that does not
      compile, with the source line of the rule set. }
    procedure LoadFromFile(const FileName: string);
    procedure LoadFromUtf8(const S: TLandrixXmlUtf8);
    { a rule file already parsed (the document is only read) }
    procedure LoadFromDocument(Document: TLandrixXmlDocument);
    { an ISO Schematron file, compiled with TLandrixXmlSchematronCompiler
      (no overrides); raises its errors too }
    procedure LoadFromSchematronFile(const FileName: string);
    property Title: TLandrixXmlUtf8 read FTitle;
    { the file the rules were compiled from and its SHA-256 }
    property Source: TLandrixXmlUtf8 read FSource;
    property Sha256: TLandrixXmlUtf8 read FSha256;
    property PatternCount: Integer read GetPatternCount;
    property Patterns[Index: Integer]: TLandrixXmlSchematronPattern read GetPattern;
  end;

  TLandrixXmlSchematronResult = class
  private
    FKind: TLandrixXmlSchematronResultKind;
    FId: TLandrixXmlUtf8;
    FFlag: TLandrixXmlUtf8;
    FRole: TLandrixXmlUtf8;
    FTest: TLandrixXmlUtf8;
    FMessage: TLandrixXmlUtf8;
    FLocation: TLandrixXmlUtf8;
    FLine: Integer;
    FColumn: Integer;
    FNode: TLandrixXmlNode;
    FPattern: TLandrixXmlUtf8;
    FRuleContext: TLandrixXmlUtf8;
    FErrorCode: string;
    { for SVRL: the index of the pattern and of the fired rule's event
      (-1 for an error in a rule context) }
    FPatternIndex: Integer;
    FEvent: Integer;
  public
    property Kind: TLandrixXmlSchematronResultKind read FKind;
    { the id of the assert or report (BR-CO-10, ...) }
    property Id: TLandrixXmlUtf8 read FId;
    { as written in the rule set: fatal, warning, information, ... }
    property Flag: TLandrixXmlUtf8 read FFlag;
    property Role: TLandrixXmlUtf8 read FRole;
    property Test: TLandrixXmlUtf8 read FTest;
    { the message text with value-of and name filled in, white space
      normalized; for a dynamic error the error message }
    property Message: TLandrixXmlUtf8 read FMessage;
    { as SchXslt writes it (see TLandrixXmlXPathTree.LocationPathUtf8) }
    property Location: TLandrixXmlUtf8 read FLocation;
    property Line: Integer read FLine;
    property Column: Integer read FColumn;
    { the DOM node when the document was a DOM, else nil }
    property Node: TLandrixXmlNode read FNode;
    property Pattern: TLandrixXmlUtf8 read FPattern;
    property RuleContext: TLandrixXmlUtf8 read FRuleContext;
    { the XPath error code of a dynamic error (FORG0001, ...) }
    property ErrorCode: string read FErrorCode;
  end;

  TLandrixXmlSchematronValidator = class
  private
    FRules: TLandrixXmlSchematronRules;
    FResults: TObjectList;
    FIncomplete: Boolean;
    FAbortOnDynamicError: Boolean;
    FFiredRules: TStringList;
    FRecordFiredRules: Boolean;
    FDocumentUri: TLandrixXmlUtf8;
    FImplicitTimeZone: Integer;
    FCurrentDateTime: TLandrixXmlXsdDateTime;
    FHasCurrentDateTime: Boolean;
    { the rules that matched, for SVRL: fired (else suppressed by an
      earlier rule of the pattern), pattern, rule and node }
    FEventCount: Integer;
    FEventFired: array of Boolean;
    FEventPatterns: TLandrixXmlXPathIntArray;
    FEventRules: TLandrixXmlXPathIntArray;
    FEventNodes: TLandrixXmlXPathIntArray;
    { set while validating: the pattern and the event results belong to }
    FCurrentPattern: Integer;
    FCurrentEvent: Integer;
    procedure AddEvent(Fired: Boolean; Pattern, Rule, Node: Integer);
    procedure ClearResults;
    procedure SetImplicitTimeZone(Value: Integer);
    procedure SetCurrentDateTime(const Value: TLandrixXmlXsdDateTime);
    function GetResultCount: Integer;
    function GetResult(Index: Integer): TLandrixXmlSchematronResult;
    procedure AddResult(Tree: TLandrixXmlXPathTree; Kind: TLandrixXmlSchematronResultKind;
      Check: TLandrixXmlSchematronCheck; Pattern: TLandrixXmlSchematronPattern; Rule: TLandrixXmlSchematronRule;
      Node: Integer; const Message: TLandrixXmlUtf8; const Code: string);
  public
    { The rules are not owned. }
    constructor Create(Rules: TLandrixXmlSchematronRules);
    destructor Destroy; override;
    { True if there is no failed assert or successful report that counts
      as an error (every flag except warning and information) and no
      dynamic error. }
    function ValidateTree(Tree: TLandrixXmlXPathTree): Boolean;
    function ValidateFile(const FileName: string): Boolean;
    { with DOM nodes in the results; see LandrixXmlXPathTree for the DOM
      options that matter }
    function ValidateDocument(Document: TLandrixXmlDocument): Boolean;
    property ResultCount: Integer read GetResultCount;
    property Results[Index: Integer]: TLandrixXmlSchematronResult read GetResult;
    { a dynamic error occurred: not every rule was checked }
    property Incomplete: Boolean read FIncomplete;
    property AbortOnDynamicError: Boolean read FAbortOnDynamicError write FAbortOnDynamicError;
    { keep "pattern TAB context TAB location" of every fired rule (for
      comparisons with SchXslt's svrl:fired-rule) }
    property RecordFiredRules: Boolean read FRecordFiredRules write FRecordFiredRules;
    property FiredRules: TStringList read FFiredRules;
    property Rules: TLandrixXmlSchematronRules read FRules;
    { The last validation as SVRL (see the unit comment); UTF-8, indented. }
    procedure SaveSvrlToStream(Stream: TStream);
    procedure SaveSvrlToFile(const FileName: string);
    { the URI svrl:active-pattern/@documents names; ValidateFile sets it to
      the file's URI, the other Validate methods keep it }
    property DocumentUri: TLandrixXmlUtf8 read FDocumentUri write FDocumentUri;
    { the implicit time zone of the XPath evaluation (minutes east of UTC,
      -840 to 840, default 0): see TLandrixXmlXPathEvaluator }
    property ImplicitTimeZone: Integer read FImplicitTimeZone write SetImplicitTimeZone;
    { what current-dateTime() returns; if it is not set (or cleared), each
      validation reads the clock at the first use (see
      TLandrixXmlXPathEvaluator.CurrentDateTime; an invalid value raises
      ELandrixXmlError when validating) }
    property CurrentDateTime: TLandrixXmlXsdDateTime read FCurrentDateTime write SetCurrentDateTime;
    procedure ClearCurrentDateTime;
  end;

implementation

uses
  LandrixXmlWriter,
  LandrixXmlSchematronCompiler;

type
  { A global variable or a function variable: slot and expression. }
  TVariable = class
  public
    Slot: Integer;
    Expression: TLandrixXmlXPathExpression;
  end;

procedure SchemaError(const Msg: string);
begin
  raise ELandrixXmlError.CreateCode(xecSchema, 'Schematron rules: ' + Msg);
end;

function U(const S: string): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(S);
end;

function IsRules(Node: TLandrixXmlNode; const LocalName: string): Boolean;
begin
  Result := (Node <> nil) and (Node.NodeType = xntElement) and
    (Node.NamespaceUriUtf8 = LandrixXmlSchematronRulesNamespace) and (Node.LocalNameUtf8 = U(LocalName));
end;

function AttrOf(Node: TLandrixXmlNode; const Name: string): TLandrixXmlUtf8;
begin
  Result := Node.AttributeValueUtf8(U(''), U(Name));
end;

{ The sequence type of an "as" attribute (xs:string?, node()*,
  element(a) ...), its prefixes from Context; no "as": item()* without
  conversion. }
function ParseSequenceType(const S: TLandrixXmlUtf8; const Where: string;
  Context: TLandrixXmlXPathStaticContext): TLandrixXmlXPathSequenceType;
begin
  if S = '' then
  begin
    Result := LandrixXmlXPathParseSequenceType('item()*', nil);
    Result.Declared := False;
    Exit;
  end;
  try
    Result := LandrixXmlXPathParseSequenceType(S, Context);
  except
    on E: ELandrixXmlXPathError do
      raise ELandrixXmlXPathError.CreateXPath(E.XPathCode, Where + ': ' + Copy(E.Message, Length(E.XPathCode) + 3,
        MaxInt));
  end;
end;

{ Splits a rule context at the "|" outside brackets and strings and
  prefixes the branches that are not rooted with "//": the nodes an XSLT
  match pattern matches. A branch document-node() becomes "/", with
  predicates "(/)[..]"; document-node() with an argument and comments
  are not supported. }
function ContextExpression(const S: TLandrixXmlUtf8; const Where: string): TLandrixXmlUtf8;
var
  I, Depth, Start: Integer;
  Quote: AnsiChar;
  Branch: TLandrixXmlUtf8;

  function IsSpace(C: AnsiChar): Boolean;
  begin
    Result := C in [' ', #9, #10, #13];
  end;

  function Trim(const X: TLandrixXmlUtf8): TLandrixXmlUtf8;
  var
    A, B: Integer;
  begin
    A := 1;
    B := Length(X);
    while (A <= B) and IsSpace(AnsiChar(X[A])) do
      Inc(A);
    while (B >= A) and IsSpace(AnsiChar(X[B])) do
      Dec(B);
    Result := Copy(X, A, B - A + 1);
  end;

  { the rest after a leading document-node(), or False }
  function DocumentNodeTest(const X: TLandrixXmlUtf8; out Rest: TLandrixXmlUtf8): Boolean;
  const
    Name = 'document-node';
  var
    J: Integer;
  begin
    Result := False;
    Rest := '';
    if Copy(X, 1, Length(Name)) <> Name then
      Exit;
    J := Length(Name) + 1;
    while (J <= Length(X)) and IsSpace(AnsiChar(X[J])) do
      Inc(J);
    if (J > Length(X)) or (X[J] <> '(') then
      Exit;
    Inc(J);
    while (J <= Length(X)) and IsSpace(AnsiChar(X[J])) do
      Inc(J);
    if (J > Length(X)) or (X[J] <> ')') then
      raise ELandrixXmlError.CreateCode(xecUnsupported, 'Schematron rules: ' + Where +
        ': document-node() with an argument in a rule context is not supported');
    Rest := Trim(Copy(X, J + 1, MaxInt));
    Result := True;
  end;

  procedure Add;
  var
    Rest: TLandrixXmlUtf8;
  begin
    Branch := Trim(Copy(S, Start, I - Start));
    if Result <> '' then
      Result := Result + ' | ';
    if DocumentNodeTest(Branch, Rest) then
    begin
      if Rest = '' then
        Result := Result + '/'
      else if Rest[1] = '[' then
        Result := Result + '(/)' + Rest
      else
        raise ELandrixXmlError.CreateCode(xecUnsupported, 'Schematron rules: ' + Where +
          ': this use of document-node() in a rule context is not supported');
    end
    else if (Branch <> '') and (Branch[1] = '/') then
      Result := Result + Branch
    else
      Result := Result + '//' + Branch;
  end;

begin
  Result := '';
  Depth := 0;
  Quote := #0;
  Start := 1;
  I := 1;
  while I <= Length(S) do
  begin
    if Quote <> #0 then
    begin
      if AnsiChar(S[I]) = Quote then
        Quote := #0;
    end
    else
      case S[I] of
        '''', '"': Quote := AnsiChar(S[I]);
        '(':
          begin
            if (I < Length(S)) and (S[I + 1] = ':') then
              raise ELandrixXmlError.CreateCode(xecUnsupported, 'Schematron rules: ' + Where +
                ': comments in a rule context are not supported');
            Inc(Depth);
          end;
        '[': Inc(Depth);
        ')', ']': Dec(Depth);
        '|':
          if Depth = 0 then
          begin
            Add;
            Start := I + 1;
          end;
      end;
    Inc(I);
  end;
  Add;
end;

{ --- rule objects ------------------------------------------------------ }

destructor TLandrixXmlSchematronCheck.Destroy;
begin
  { the expressions are owned by the rules object }
  inherited Destroy;
end;

constructor TLandrixXmlSchematronRule.Create;
begin
  inherited Create;
  Checks := TObjectList.Create(True);
end;

destructor TLandrixXmlSchematronRule.Destroy;
begin
  Checks.Free;
  inherited Destroy;
end;

constructor TLandrixXmlSchematronPattern.Create;
begin
  inherited Create;
  Rules := TObjectList.Create(True);
end;

destructor TLandrixXmlSchematronPattern.Destroy;
begin
  Rules.Free;
  inherited Destroy;
end;

{ --- TLandrixXmlSchematronRules ------------------------------------------ }

constructor TLandrixXmlSchematronRules.Create;
begin
  inherited Create;
  FFunctionContexts := TObjectList.Create(True);
  FGlobals := TObjectList.Create(True);
  FFunctions := TList.Create;
  FOwnedFunctions := TObjectList.Create(True);
  FPatterns := TObjectList.Create(True);
  FExpressions := TObjectList.Create(True);
  FDocuments := TObjectList.Create(True);
end;

destructor TLandrixXmlSchematronRules.Destroy;
begin
  Clear;
  FDocuments.Free;
  FFunctionContexts.Free;
  FGlobals.Free;
  FFunctions.Free;
  FOwnedFunctions.Free;
  FPatterns.Free;
  FExpressions.Free;
  inherited Destroy;
end;

procedure TLandrixXmlSchematronRules.Clear;
begin
  FDocumentUris := nil;
  FNsPrefixes := nil;
  FNsUris := nil;
  FDocuments.Clear;
  FPatterns.Clear;
  FFunctions.Clear;
  FOwnedFunctions.Clear;
  FGlobals.Clear;
  FExpressions.Clear;
  FFunctionContexts.Clear;
  FContext.Free;
  FContext := nil;
  FGlobalSlots := nil;
  FGlobalCount := 0;
  FTitle := '';
  FSource := '';
  FSha256 := '';
end;

{ Every document() must read an embedded document, named by a string
  literal. }
function TLandrixXmlSchematronRules.Compile(const Text: TLandrixXmlUtf8; Context: TLandrixXmlXPathStaticContext;
  const Where: string): TLandrixXmlXPathExpression;
var
  I, K: Integer;
  Found: Boolean;
  Arg: TLandrixXmlUtf8;
begin
  try
    Result := TLandrixXmlXPathExpression.Create(Text, Context);
  except
    on E: ELandrixXmlXPathError do
      raise ELandrixXmlXPathError.CreateXPath(E.XPathCode, Where + ': ' + Copy(E.Message, Length(E.XPathCode) + 3,
        MaxInt));
  end;
  FExpressions.Add(Result);
  for I := 0 to Result.NodeCount - 1 do
    if (Result.Nodes[I].Kind = xakFunction) and (Result.Nodes[I].Op = Ord(xfnDocument)) then
    begin
      if Result.Nodes[Result.Nodes[I].Children[0]].Kind <> xakString then
        raise ELandrixXmlError.CreateCode(xecUnsupported, 'Schematron rules: ' + Where +
          ': document() is only supported with a string literal');
      Arg := Result.Nodes[Result.Nodes[I].Children[0]].Text;
      Found := False;
      for K := 0 to Integer(Length(FDocumentUris)) - 1 do
        if FDocumentUris[K] = Arg then
          Found := True;
      if not Found then
        SchemaError(Where + ': the document ' + LandrixXmlUtf8ToString(Arg) + ' is not embedded');
    end;
end;

procedure TLandrixXmlSchematronRules.LoadFromFile(const FileName: string);
var
  Doc: TLandrixXmlDocument;
begin
  Clear;
  Doc := TLandrixXmlDocument.Create;
  try
    Doc.LoadFromFile(FileName);
    Load(Doc);
  finally
    Doc.Free;
  end;
end;

procedure TLandrixXmlSchematronRules.LoadFromUtf8(const S: TLandrixXmlUtf8);
var
  Doc: TLandrixXmlDocument;
begin
  Clear;
  Doc := TLandrixXmlDocument.Create;
  try
    Doc.LoadFromUtf8(S);
    Load(Doc);
  finally
    Doc.Free;
  end;
end;

procedure TLandrixXmlSchematronRules.LoadFromDocument(Document: TLandrixXmlDocument);
begin
  Clear;
  Load(Document);
end;

procedure TLandrixXmlSchematronRules.LoadFromSchematronFile(const FileName: string);
var
  Compiler: TLandrixXmlSchematronCompiler;
  Doc: TLandrixXmlDocument;
begin
  Clear;
  Compiler := TLandrixXmlSchematronCompiler.Create;
  try
    Doc := Compiler.CompileFile(FileName);
    try
      Load(Doc);
    finally
      Doc.Free;
    end;
  finally
    Compiler.Free;
  end;
end;

{ the text content of an element }
function TextOf(Node: TLandrixXmlNode): TLandrixXmlUtf8;
var
  C: TLandrixXmlNode;
begin
  Result := '';
  C := Node.FirstChild;
  while C <> nil do
  begin
    if C.NodeType in [LandrixXmlDom.xntText, LandrixXmlDom.xntCData] then
      Result := Result + C.ValueUtf8;
    C := C.NextSibling;
  end;
end;

procedure TLandrixXmlSchematronRules.Load(Document: TLandrixXmlDocument);
var
  Root, N, F, R, C, P: TLandrixXmlNode;
  Doc: TLandrixXmlXPathTree;
  Name: TLandrixXmlUtf8;
  I, K, Slot: Integer;
  Ctx: TLandrixXmlXPathStaticContext;
  Def: TLandrixXmlXPathFunctionDef;
  Variable: TVariable;
  Pattern: TLandrixXmlSchematronPattern;
  Rule: TLandrixXmlSchematronRule;
  Check: TLandrixXmlSchematronCheck;
  Names: TLandrixXmlUtf8Array;
  NameCount: Integer;
  RuleSlots: array of Integer;
  Where: string;

  { prefix and local name of a QName, split on the bytes }
  procedure SplitName(const Q: TLandrixXmlUtf8; out Prefix, Local: TLandrixXmlUtf8);
  var
    J: Integer;
  begin
    Prefix := '';
    Local := Q;
    for J := 1 to Length(Q) do
      if Q[J] = ':' then
      begin
        Prefix := Copy(Q, 1, J - 1);
        Local := Copy(Q, J + 1, MaxInt);
        Break;
      end;
  end;

  { the slot of a variable by its expanded name, or -1; all prefixes
    bound to one URI name the same variable }
  function SlotOf(Target: TLandrixXmlXPathStaticContext; const Q: TLandrixXmlUtf8): Integer;
  var
    Prefix, Local, Uri: TLandrixXmlUtf8;
  begin
    SplitName(Q, Prefix, Local);
    Uri := '';
    if (Prefix <> '') and not Target.LookupNamespace(Prefix, Uri) then
      SchemaError('the prefix of variable $' + LandrixXmlUtf8ToString(Q) + ' is not declared');
    Result := Target.FindVariable(Uri, Local);
  end;

  procedure DeclareNamespaces(Target: TLandrixXmlXPathStaticContext);
  var
    X: TLandrixXmlNode;
  begin
    X := Root.FirstChildElement;
    while X <> nil do
    begin
      if IsRules(X, 'ns') then
        Target.AddNamespace(AttrOf(X, 'prefix'), AttrOf(X, 'uri'));
      X := X.NextSiblingElement;
    end;
  end;

  procedure DeclareCommon(Target: TLandrixXmlXPathStaticContext);
  var
    J: Integer;
  begin
    DeclareNamespaces(Target);
    for J := 0 to NameCount - 1 do
      Target.DeclareVariable(Names[J]);
  end;

  function UsesCurrent(Expr: TLandrixXmlXPathExpression): Boolean;
  var
    J: Integer;
  begin
    Result := False;
    for J := 0 to Expr.NodeCount - 1 do
      if (Expr.Nodes[J].Kind = xakFunction) and (Expr.Nodes[J].Op = Ord(xfnCurrent)) then
      begin
        Result := True;
        Exit;
      end;
  end;

  { intersect or except outside the predicates: XSLT 2.0 patterns have
    only "|", and the branches of a rule context are made relative to the
    document by "//" (ContextExpression), which these operators would
    change the meaning of }
  function UsesSetOperator(Expr: TLandrixXmlXPathExpression; Index: Integer): Boolean;
  var
    J: Integer;
  begin
    Result := Expr.Nodes[Index].Kind = xakIntersectExcept;
    J := 0;
    while not Result and (J < Length(Expr.Nodes[Index].Children)) do
    begin
      Result := UsesSetOperator(Expr, Expr.Nodes[Index].Children[J]);
      Inc(J);
    end;
  end;

  procedure DeclareFunctions(Target: TLandrixXmlXPathStaticContext; CheckDuplicates: Boolean);
  var
    X, Y: TLandrixXmlNode;
    Q, P, L, NsUri: TLandrixXmlUtf8;
    Count: Integer;
  begin
    X := Root.FirstChildElement;
    while X <> nil do
    begin
      if IsRules(X, 'function') then
      begin
        Q := AttrOf(X, 'name');
        SplitName(Q, P, L);
        if P = '' then
          SchemaError('a function without prefix: ' + LandrixXmlUtf8ToString(Q));
        if not Target.LookupNamespace(P, NsUri) then
          SchemaError('the prefix of function ' + LandrixXmlUtf8ToString(Q) + ' is not declared');
        Count := 0;
        Y := X.FirstChildElement;
        while Y <> nil do
        begin
          if IsRules(Y, 'param') then
            Inc(Count);
          Y := Y.NextSiblingElement;
        end;
        if CheckDuplicates and (Target.FindFunction(NsUri, L, Count) >= 0) then
          SchemaError('the function ' + LandrixXmlUtf8ToString(Q) + '#' + IntToStr(Count) + ' is defined twice');
        Target.DeclareFunction(NsUri, L, Count);
      end;
      X := X.NextSiblingElement;
    end;
  end;

begin
  Clear;
  Root := Document.Root;
  if not IsRules(Root, 'rules') then
    SchemaError('not a rule file (root element rules in ' + LandrixXmlSchematronRulesNamespace + ' expected)');
  { 2: with embedded documents }
  if (AttrOf(Root, 'format') <> '1') and (AttrOf(Root, 'format') <> '2') then
    SchemaError('unsupported rule file format "' + LandrixXmlUtf8ToString(AttrOf(Root, 'format')) + '"');
  FTitle := AttrOf(Root, 'title');
  FSource := AttrOf(Root, 'source');
  FSha256 := AttrOf(Root, 'sha256');
  Names := nil;
  NameCount := 0;
  RuleSlots := nil;
  try
    try
      { the globals first: their slots are the same in every context }
      FContext := TLandrixXmlXPathStaticContext.Create;
      FContext.Profile := xppSaxon;
      DeclareNamespaces(FContext);
      N := Root.FirstChildElement;
      while N <> nil do
      begin
        if IsRules(N, 'let') then
        begin
          Name := AttrOf(N, 'name');
          if SlotOf(FContext, Name) >= 0 then
            SchemaError('the global variable $' + LandrixXmlUtf8ToString(Name) + ' is defined twice');
          FContext.DeclareVariable(Name);
          if NameCount = Length(Names) then
            SetLength(Names, 2 * NameCount + 8);
          Names[NameCount] := Name;
          Inc(NameCount);
        end;
        N := N.NextSiblingElement;
      end;
      FGlobalCount := NameCount;
      N := Root.FirstChildElement;
      while N <> nil do
      begin
        if IsRules(N, 'ns') then
        begin
          I := Integer(Length(FNsPrefixes));
          SetLength(FNsPrefixes, I + 1);
          SetLength(FNsUris, I + 1);
          FNsPrefixes[I] := AttrOf(N, 'prefix');
          FNsUris[I] := AttrOf(N, 'uri');
        end;
        N := N.NextSiblingElement;
      end;
      { the documents document() reads, each as a tree of its own }
      N := Root.FirstChildElement;
      while N <> nil do
      begin
        if IsRules(N, 'document') then
        begin
          Name := AttrOf(N, 'href');
          for I := 0 to Integer(Length(FDocumentUris)) - 1 do
            if FDocumentUris[I] = Name then
              SchemaError('the document ' + LandrixXmlUtf8ToString(Name) + ' is embedded twice');
          Doc := TLandrixXmlXPathTree.Create;
          FDocuments.Add(Doc);
          Doc.LoadFromUtf8(TextOf(N));
          I := Integer(Length(FDocumentUris));
          SetLength(FDocumentUris, I + 1);
          FDocumentUris[I] := Name;
        end;
        N := N.NextSiblingElement;
      end;
      { the rule variables after the globals, one slot per expanded name; a
        rule variable must not hide a global or another variable of its rule }
      N := Root.FirstChildElement;
      while N <> nil do
      begin
        if IsRules(N, 'pattern') then
        begin
          R := N.FirstChildElement;
          while R <> nil do
          begin
            RuleSlots := nil;
            C := R.FirstChildElement;
            while C <> nil do
            begin
              if IsRules(C, 'let') then
              begin
                Name := AttrOf(C, 'name');
                Slot := SlotOf(FContext, Name);
                if (Slot >= 0) and (Slot < FGlobalCount) then
                  SchemaError('the rule variable $' + LandrixXmlUtf8ToString(Name) + ' hides a global variable');
                if Slot < 0 then
                  Slot := FContext.DeclareVariable(Name);
                for I := 0 to Integer(Length(RuleSlots)) - 1 do
                  if RuleSlots[I] = Slot then
                    SchemaError('the rule variable $' + LandrixXmlUtf8ToString(Name) + ' is defined twice');
                I := Integer(Length(RuleSlots));
                SetLength(RuleSlots, I + 1);
                RuleSlots[I] := Slot;
              end;
              C := C.NextSiblingElement;
            end;
            R := R.NextSiblingElement;
          end;
        end;
        N := N.NextSiblingElement;
      end;
      DeclareFunctions(FContext, True);
      { functions: a context each, with the globals, then params and variables }
      N := Root.FirstChildElement;
      while N <> nil do
      begin
        if IsRules(N, 'function') then
        begin
          Where := LandrixXmlUtf8ToString(AttrOf(N, 'line'));
          Ctx := TLandrixXmlXPathStaticContext.Create;
          Ctx.Profile := xppSaxon;
          FFunctionContexts.Add(Ctx);
          DeclareCommon(Ctx);
          Def := TLandrixXmlXPathFunctionDef.Create;
          FOwnedFunctions.Add(Def);
          FFunctions.Add(Def);
          Def.Name := LandrixXmlUtf8ToString(AttrOf(N, 'name'));
          Def.ResultType := ParseSequenceType(AttrOf(N, 'as'), Where, Ctx);
          F := N.FirstChildElement;
          while F <> nil do
          begin
            if IsRules(F, 'param') or IsRules(F, 'variable') then
            begin
              Name := AttrOf(F, 'name');
              if SlotOf(Ctx, Name) >= 0 then
                SchemaError(Where + ': $' + LandrixXmlUtf8ToString(Name) + ' hides another variable');
              Slot := Ctx.DeclareVariable(Name);
              if IsRules(F, 'param') then
              begin
                I := Integer(Length(Def.ParamSlots));
                SetLength(Def.ParamSlots, I + 1);
                SetLength(Def.ParamTypes, I + 1);
                Def.ParamSlots[I] := Slot;
                Def.ParamTypes[I] := ParseSequenceType(AttrOf(F, 'as'), Where, Ctx);
              end
              else
              begin
                I := Integer(Length(Def.LocalSlots));
                SetLength(Def.LocalSlots, I + 1);
                SetLength(Def.LocalTypes, I + 1);
                SetLength(Def.LocalExpressions, I + 1);
                Def.LocalSlots[I] := Slot;
                Def.LocalTypes[I] := ParseSequenceType(AttrOf(F, 'as'), Where, Ctx);
              end;
            end;
            F := F.NextSiblingElement;
          end;
          DeclareFunctions(Ctx, False);
          Def.FrameSize := Ctx.VariableCount;
        end;
        N := N.NextSiblingElement;
      end;
      { now the expressions (functions may call each other) }
      K := 0;
      N := Root.FirstChildElement;
      while N <> nil do
      begin
        if IsRules(N, 'let') then
        begin
          Variable := TVariable.Create;
          FGlobals.Add(Variable);
          Variable.Slot := SlotOf(FContext, AttrOf(N, 'name'));
          Variable.Expression := Compile(AttrOf(N, 'value'), FContext, LandrixXmlUtf8ToString(AttrOf(N, 'line')));
        end
        else if IsRules(N, 'function') then
        begin
          Where := LandrixXmlUtf8ToString(AttrOf(N, 'line'));
          Def := TLandrixXmlXPathFunctionDef(FFunctions[K]);
          Ctx := TLandrixXmlXPathStaticContext(FFunctionContexts[K]);
          Inc(K);
          I := 0;
          F := N.FirstChildElement;
          while F <> nil do
          begin
            if IsRules(F, 'variable') then
            begin
              Def.LocalExpressions[I] := Compile(AttrOf(F, 'value'), Ctx, Where);
              Inc(I);
            end
            else if IsRules(F, 'result') then
              Def.Body := Compile(AttrOf(F, 'value'), Ctx, Where);
            F := F.NextSiblingElement;
          end;
          if Def.Body = nil then
            SchemaError(Where + ': a function without result');
        end
        else if IsRules(N, 'pattern') then
        begin
          Pattern := TLandrixXmlSchematronPattern.Create;
          FPatterns.Add(Pattern);
          Pattern.Id := AttrOf(N, 'id');
          R := N.FirstChildElement;
          while R <> nil do
          begin
            if IsRules(R, 'rule') then
            begin
              Rule := TLandrixXmlSchematronRule.Create;
              Pattern.Rules.Add(Rule);
              Rule.Id := AttrOf(R, 'id');
              Rule.Flag := AttrOf(R, 'flag');
              Rule.Role := AttrOf(R, 'role');
              Rule.SourceLine := LandrixXmlUtf8ToString(AttrOf(R, 'line'));
              Rule.ContextText := AttrOf(R, 'context');
              Rule.Context := Compile(ContextExpression(Rule.ContextText, Rule.SourceLine), FContext,
                Rule.SourceLine);
              if UsesCurrent(Rule.Context) then
                raise ELandrixXmlError.CreateCode(xecUnsupported, 'Schematron rules: ' + Rule.SourceLine +
                  ': current() in a rule context is not supported');
              if UsesSetOperator(Rule.Context, Rule.Context.Root) then
                raise ELandrixXmlError.CreateCode(xecUnsupported, 'Schematron rules: ' + Rule.SourceLine +
                  ': intersect and except in a rule context are not supported');
              C := R.FirstChildElement;
              while C <> nil do
              begin
                if IsRules(C, 'let') then
                begin
                  I := Integer(Length(Rule.Lets));
                  SetLength(Rule.Lets, I + 1);
                  SetLength(Rule.LetSlots, I + 1);
                  Rule.LetSlots[I] := SlotOf(FContext, AttrOf(C, 'name'));
                  Rule.Lets[I] := Compile(AttrOf(C, 'value'), FContext, Rule.SourceLine);
                end
                else if IsRules(C, 'assert') or IsRules(C, 'report') then
                begin
                  Check := TLandrixXmlSchematronCheck.Create;
                  Rule.Checks.Add(Check);
                  Check.IsReport := IsRules(C, 'report');
                  Check.Id := AttrOf(C, 'id');
                  Check.Flag := AttrOf(C, 'flag');
                  Check.Role := AttrOf(C, 'role');
                  Check.TestText := AttrOf(C, 'test');
                  Check.SourceLine := LandrixXmlUtf8ToString(AttrOf(C, 'line'));
                  Check.Test := Compile(Check.TestText, FContext, Check.SourceLine);
                  P := C.FirstChildElement;
                  while P <> nil do
                  begin
                    I := Integer(Length(Check.Parts));
                    SetLength(Check.Parts, I + 1);
                    Check.Parts[I].Expression := nil;
                    Check.Parts[I].Text := '';
                    if IsRules(P, 'text') then
                    begin
                      Check.Parts[I].Kind := xspText;
                      Check.Parts[I].Text := P.TextUtf8;
                    end
                    else if IsRules(P, 'value-of') then
                    begin
                      Check.Parts[I].Kind := xspValueOf;
                      Check.Parts[I].Expression := Compile(AttrOf(P, 'select'), FContext, Check.SourceLine);
                    end
                    else if IsRules(P, 'name') then
                    begin
                      Check.Parts[I].Kind := xspName;
                      if AttrOf(P, 'path') = '' then
                        Check.Parts[I].Expression := Compile('name()', FContext, Check.SourceLine)
                      else
                        Check.Parts[I].Expression := Compile('name(' + AttrOf(P, 'path') + ')', FContext,
                          Check.SourceLine);
                    end
                    else
                      SchemaError(Check.SourceLine + ': unexpected element in a message');
                    P := P.NextSiblingElement;
                  end;
                end;
                C := C.NextSiblingElement;
              end;
            end;
            R := R.NextSiblingElement;
          end;
        end
        else if not (IsRules(N, 'ns') or IsRules(N, 'document')) then
          SchemaError('unexpected element ' + LandrixXmlUtf8ToString(N.NameUtf8));
        N := N.NextSiblingElement;
      end;
    finally
      Names := nil;
      RuleSlots := nil;
    end;
  except
    Clear;
    raise;
  end;
end;

function TLandrixXmlSchematronRules.GetPatternCount: Integer;
begin
  Result := Integer(FPatterns.Count);
end;

function TLandrixXmlSchematronRules.GetPattern(Index: Integer): TLandrixXmlSchematronPattern;
begin
  Result := TLandrixXmlSchematronPattern(FPatterns[Index]);
end;

{ --- TLandrixXmlSchematronValidator ------------------------------------------ }

procedure TLandrixXmlSchematronValidator.SetImplicitTimeZone(Value: Integer);
begin
  if (Value < -840) or (Value > 840) then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'ImplicitTimeZone must be between -840 and 840 minutes');
  FImplicitTimeZone := Value;
end;

procedure TLandrixXmlSchematronValidator.SetCurrentDateTime(const Value: TLandrixXmlXsdDateTime);
begin
  FCurrentDateTime := Value;
  FHasCurrentDateTime := True;
end;

procedure TLandrixXmlSchematronValidator.ClearCurrentDateTime;
begin
  FHasCurrentDateTime := False;
end;

constructor TLandrixXmlSchematronValidator.Create(Rules: TLandrixXmlSchematronRules);
begin
  inherited Create;
  if Rules = nil then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'A Schematron validator needs rules');
  FRules := Rules;
  FResults := TObjectList.Create(True);
  FFiredRules := TStringList.Create;
end;

destructor TLandrixXmlSchematronValidator.Destroy;
begin
  FResults.Free;
  FFiredRules.Free;
  inherited Destroy;
end;

function TLandrixXmlSchematronValidator.GetResultCount: Integer;
begin
  Result := Integer(FResults.Count);
end;

function TLandrixXmlSchematronValidator.GetResult(Index: Integer): TLandrixXmlSchematronResult;
begin
  Result := TLandrixXmlSchematronResult(FResults[Index]);
end;

procedure TLandrixXmlSchematronValidator.AddResult(Tree: TLandrixXmlXPathTree; Kind: TLandrixXmlSchematronResultKind;
  Check: TLandrixXmlSchematronCheck; Pattern: TLandrixXmlSchematronPattern; Rule: TLandrixXmlSchematronRule;
  Node: Integer; const Message: TLandrixXmlUtf8; const Code: string);
var
  R: TLandrixXmlSchematronResult;
begin
  R := TLandrixXmlSchematronResult.Create;
  FResults.Add(R);
  R.FKind := Kind;
  if Check <> nil then
  begin
    R.FId := Check.Id;
    R.FFlag := Check.Flag;
    R.FRole := Check.Role;
    R.FTest := Check.TestText;
  end;
  R.FMessage := Message;
  R.FErrorCode := Code;
  R.FPatternIndex := FCurrentPattern;
  R.FEvent := FCurrentEvent;
  if Node >= 0 then
  begin
    R.FLocation := Tree.LocationPathUtf8(Node);
    R.FLine := Tree.Line[Node];
    R.FColumn := Tree.Column[Node];
    R.FNode := Tree.DomNode[Node];
  end;
  if Pattern <> nil then
    R.FPattern := Pattern.Id;
  if Rule <> nil then
    R.FRuleContext := Rule.ContextText;
end;

function NormalizedText(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I, N: Integer;
  Space: Boolean;
begin
  Result := '';
  SetLength(Result, Length(S));
  N := 0;
  Space := False;
  for I := 1 to Length(S) do
    if S[I] in [' ', #9, #10, #13] then
      Space := N > 0
    else
    begin
      if Space then
      begin
        Inc(N);
        Result[N] := ' ';
        Space := False;
      end;
      Inc(N);
      Result[N] := S[I];
    end;
  SetLength(Result, N);
end;

function TLandrixXmlSchematronValidator.ValidateTree(Tree: TLandrixXmlXPathTree): Boolean;
var
  E: TLandrixXmlXPathEvaluator;
  P, R, K, I, J, Node, RuleIndex, Link, LinkCount: Integer;
  Pattern: TLandrixXmlSchematronPattern;
  Rule: TLandrixXmlSchematronRule;
  Check: TLandrixXmlSchematronCheck;
  { per node the rules of the pattern whose context contains it, the first
    (in schema order) at First[Node], the others along LinkNext }
  First: array of Integer;
  LinkRule, LinkNext: array of Integer;
  Nodes: TLandrixXmlXPathSequence;
  Value: Boolean;
  Message: TLandrixXmlUtf8;
  Aborted: Boolean;

  { a dynamic error: a result, and the end if Saxon's behaviour is wanted }
  procedure DynamicError(X: ELandrixXmlXPathError; C: TLandrixXmlSchematronCheck; AtNode: Integer);
  begin
    FIncomplete := True;
    AddResult(Tree, xsrDynamicError, C, Pattern, Rule, AtNode, U(X.Message), X.XPathCode);
    if FAbortOnDynamicError then
      Aborted := True;
  end;

  function MessageOf(C: TLandrixXmlSchematronCheck; AtNode: Integer): TLandrixXmlUtf8;
  var
    Q: Integer;
  begin
    Result := '';
    for Q := 0 to Integer(Length(C.Parts)) - 1 do
      if C.Parts[Q].Kind = xspText then
        Result := Result + C.Parts[Q].Text
      else
        Result := Result + E.EvaluateString(C.Parts[Q].Expression, AtNode);
    Result := NormalizedText(Result);
  end;

begin
  if Tree.Kind[0] <> xnkDocument then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'Schematron: the tree has no document node');
  ClearResults;
  FCurrentPattern := -1;
  FCurrentEvent := -1;
  Aborted := False;
  Pattern := nil;
  Rule := nil;
  First := nil;
  LinkRule := nil;
  LinkNext := nil;
  if FRules.FContext = nil then
    raise ELandrixXmlError.CreateCode(xecInvalidOperation, 'No Schematron rules are loaded');
  E := TLandrixXmlXPathEvaluator.Create(Tree);
  try
    E.ImplicitTimeZone := FImplicitTimeZone;
    if FHasCurrentDateTime then
      E.CurrentDateTime := FCurrentDateTime;
    E.Functions := FRules.FFunctions;
    E.SetGlobalCount(FRules.FGlobalCount);
    E.SetFrameSize(FRules.FContext.VariableCount);
    for I := 0 to Integer(Length(FRules.FDocumentUris)) - 1 do
      E.AddDocument(FRules.FDocumentUris[I], TLandrixXmlXPathTree(FRules.FDocuments[I]));
    for I := 0 to Integer(FRules.FGlobals.Count) - 1 do
      E.BindLazy(TVariable(FRules.FGlobals[I]).Slot, TVariable(FRules.FGlobals[I]).Expression, 0);
    SetLength(First, Tree.Count);
    for P := 0 to FRules.PatternCount - 1 do
    begin
      if Aborted then
        Break;
      Pattern := FRules.Patterns[P];
      FCurrentPattern := P;
      FCurrentEvent := -1;
      { the nodes of each rule's context; the first rule wins }
      for Node := 0 to Tree.Count - 1 do
        First[Node] := -1;
      LinkCount := 0;
      for R := Integer(Pattern.Rules.Count) - 1 downto 0 do
      begin
        Rule := TLandrixXmlSchematronRule(Pattern.Rules[R]);
        try
          Nodes := E.EvaluatePattern(Rule.Context, 0);
        except
          on X: ELandrixXmlXPathError do
          begin
            DynamicError(X, nil, -1);
            Nodes := LandrixXmlXPathEmpty;
          end;
        end;
        if Aborted then
          Break;
        { only nodes of the document match (not of embedded documents);
          the rules come last to first, so each node's list is in order }
        for K := 0 to Nodes.Count - 1 do
          if (Nodes.Items[K].Kind = xikNode) and (Nodes.Items[K].Node < Tree.Count) then
          begin
            if LinkCount = Length(LinkRule) then
            begin
              SetLength(LinkRule, 2 * LinkCount + 64);
              SetLength(LinkNext, 2 * LinkCount + 64);
            end;
            LinkRule[LinkCount] := R;
            LinkNext[LinkCount] := First[Nodes.Items[K].Node];
            First[Nodes.Items[K].Node] := LinkCount;
            Inc(LinkCount);
          end;
      end;
      Nodes := LandrixXmlXPathEmpty;
      if Aborted then
        Break;
      for Node := 0 to Tree.Count - 1 do
      begin
        if First[Node] < 0 then
          Continue;
        RuleIndex := LinkRule[First[Node]];
        Rule := TLandrixXmlSchematronRule(Pattern.Rules[RuleIndex]);
        AddEvent(True, P, RuleIndex, Node);
        FCurrentEvent := FEventCount - 1;
        if FRecordFiredRules then
          FFiredRules.Add(LandrixXmlUtf8ToString(Pattern.Id + #9 + Rule.ContextText + #9 + Tree.LocationPathUtf8(Node)));
        E.UnbindFrame;
        E.CurrentNode := Node;
        for J := 0 to Integer(Length(Rule.Lets)) - 1 do
          E.BindLazy(Rule.LetSlots[J], Rule.Lets[J], Node);
        for J := 0 to Integer(Rule.Checks.Count) - 1 do
        begin
          Check := TLandrixXmlSchematronCheck(Rule.Checks[J]);
          try
            Value := E.EvaluateBoolean(Check.Test, Node);
            if Value = Check.IsReport then
            begin
              Message := MessageOf(Check, Node);
              if Check.IsReport then
                AddResult(Tree, xsrSuccessfulReport, Check, Pattern, Rule, Node, Message, '')
              else
                AddResult(Tree, xsrFailedAssert, Check, Pattern, Rule, Node, Message, '');
            end;
          except
            on X: ELandrixXmlXPathError do
              DynamicError(X, Check, Node);
          end;
          if Aborted then
            Break;
        end;
        if Aborted then
          Break;
        { the later rules of the pattern for this node: shadowed }
        Link := LinkNext[First[Node]];
        while Link >= 0 do
        begin
          AddEvent(False, P, LinkRule[Link], Node);
          Link := LinkNext[Link];
        end;
      end;
    end;
  finally
    E.Free;
    FCurrentPattern := -1;
    FCurrentEvent := -1;
  end;
  Result := not FIncomplete;
  for I := 0 to Integer(FResults.Count) - 1 do
    if (Results[I].Kind <> xsrDynamicError) and (Results[I].Flag <> 'warning') and (Results[I].Flag <> 'information') then
      Result := False;
end;

procedure TLandrixXmlSchematronValidator.ClearResults;
begin
  FResults.Clear;
  FFiredRules.Clear;
  FEventCount := 0;
  FIncomplete := False;
end;

procedure TLandrixXmlSchematronValidator.AddEvent(Fired: Boolean; Pattern, Rule, Node: Integer);
begin
  if FEventCount = Length(FEventPatterns) then
  begin
    SetLength(FEventFired, 2 * FEventCount + 64);
    SetLength(FEventPatterns, 2 * FEventCount + 64);
    SetLength(FEventRules, 2 * FEventCount + 64);
    SetLength(FEventNodes, 2 * FEventCount + 64);
  end;
  FEventFired[FEventCount] := Fired;
  FEventPatterns[FEventCount] := Pattern;
  FEventRules[FEventCount] := Rule;
  FEventNodes[FEventCount] := Node;
  Inc(FEventCount);
end;

{ the text of an XML comment ("--" may not occur in it) }
function CommentText(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    if (S[I] = '-') and (Copy(Result, Length(Result), 1) = '-') then
      Result := Result + ' -'
    else
      Result := Result + Copy(S, I, 1);
  if Copy(Result, Length(Result), 1) = '-' then
    Result := Result + ' ';
end;

procedure TLandrixXmlSchematronValidator.SaveSvrlToStream(Stream: TStream);
const
  Svrl = 'http://purl.oclc.org/dsdl/svrl';
var
  W: TLandrixXmlWriter;
  P, I, Ev, Next: Integer;
  Pattern: TLandrixXmlSchematronPattern;
  Rule: TLandrixXmlSchematronRule;
  R: TLandrixXmlSchematronResult;

  procedure Error(Res: TLandrixXmlSchematronResult);
  begin
    W.CommentUtf8(CommentText(' dynamic error ' + LandrixXmlStringToUtf8(Res.ErrorCode) + ' ' + Res.Location +
      ': ' + Res.Message + ' '));
  end;

  { the results (in order) that belong to event Ev of pattern P }
  procedure Results(Ev: Integer);
  begin
    while (Next < FResults.Count) and (TLandrixXmlSchematronResult(FResults[Next]).FPatternIndex = P) and
      (TLandrixXmlSchematronResult(FResults[Next]).FEvent = Ev) do
    begin
      R := TLandrixXmlSchematronResult(FResults[Next]);
      Inc(Next);
      if R.Kind = xsrDynamicError then
      begin
        Error(R);
        Continue;
      end;
      if R.Kind = xsrFailedAssert then
        W.StartElementNs(Svrl, 'svrl', 'failed-assert')
      else
        W.StartElementNs(Svrl, 'svrl', 'successful-report');
      W.AttributeUtf8('location', R.Location);
      if R.Flag <> '' then
        W.AttributeUtf8('flag', R.Flag);
      if R.Id <> '' then
        W.AttributeUtf8('id', R.Id);
      if R.Role <> '' then
        W.AttributeUtf8('role', R.Role);
      W.AttributeUtf8('test', R.Test);
      W.ElementNsUtf8(Svrl, 'svrl', 'text', R.Message);
      W.EndElement;
    end;
  end;

begin
  W := TLandrixXmlWriter.Create(Stream);
  try
    W.Indent := True;
    W.StartDocument;
    W.StartElementNs(Svrl, 'svrl', 'schematron-output');
    if FRules.Title <> '' then
      W.AttributeUtf8('title', FRules.Title);
    for I := 0 to Integer(Length(FRules.FNsPrefixes)) - 1 do
    begin
      W.StartElementNs(Svrl, 'svrl', 'ns-prefix-in-attribute-values');
      W.AttributeUtf8('prefix', FRules.FNsPrefixes[I]);
      W.AttributeUtf8('uri', FRules.FNsUris[I]);
      W.EndElement;
    end;
    Next := 0;
    Ev := 0;
    for P := 0 to FRules.PatternCount - 1 do
    begin
      Pattern := FRules.Patterns[P];
      W.StartElementNs(Svrl, 'svrl', 'active-pattern');
      if Pattern.Id <> '' then
      begin
        W.AttributeUtf8('name', Pattern.Id);
        W.AttributeUtf8('id', Pattern.Id);
      end;
      if FDocumentUri <> '' then
        W.AttributeUtf8('documents', FDocumentUri);
      W.EndElement;
      { errors in a rule context of the pattern }
      Results(-1);
      while (Ev < FEventCount) and (FEventPatterns[Ev] = P) do
      begin
        Rule := TLandrixXmlSchematronRule(Pattern.Rules[FEventRules[Ev]]);
        if FEventFired[Ev] then
        begin
          W.StartElementNs(Svrl, 'svrl', 'fired-rule');
          W.AttributeUtf8('context', Rule.ContextText);
          if Rule.Id <> '' then
            W.AttributeUtf8('id', Rule.Id);
          if Rule.Role <> '' then
            W.AttributeUtf8('role', Rule.Role);
          if Rule.Flag <> '' then
            W.AttributeUtf8('flag', Rule.Flag);
          W.EndElement;
          Results(Ev);
        end
        else
        begin
          W.CommentUtf8('WARNING: Rule for context "' + CommentText(Rule.ContextText) +
            '" shadowed by preceding rule');
          W.StartElementNs(Svrl, 'svrl', 'suppressed-rule');
          W.AttributeUtf8('context', Rule.ContextText);
          W.EndElement;
        end;
        Inc(Ev);
      end;
    end;
    W.EndElement;
    W.EndDocument;
  finally
    W.Free;
  end;
end;

procedure TLandrixXmlSchematronValidator.SaveSvrlToFile(const FileName: string);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(FileName, fmCreate);
  try
    SaveSvrlToStream(Stream);
  finally
    Stream.Free;
  end;
end;

function TLandrixXmlSchematronValidator.ValidateFile(const FileName: string): Boolean;
var
  Tree: TLandrixXmlXPathTree;
begin
  { a document that does not load leaves no results of the one before }
  ClearResults;
  Tree := TLandrixXmlXPathTree.Create;
  try
    Tree.LoadFromFile(FileName);
    FDocumentUri := Tree.BaseUri;
    Result := ValidateTree(Tree);
  finally
    Tree.Free;
  end;
end;

function TLandrixXmlSchematronValidator.ValidateDocument(Document: TLandrixXmlDocument): Boolean;
var
  Tree: TLandrixXmlXPathTree;
begin
  ClearResults;
  Tree := TLandrixXmlXPathTree.Create;
  try
    Tree.LoadFromDocument(Document);
    Result := ValidateTree(Tree);
  finally
    Tree.Free;
  end;
end;

end.
