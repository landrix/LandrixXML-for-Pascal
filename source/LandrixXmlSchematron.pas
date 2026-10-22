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
  end;

implementation

uses
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

{ An XPath sequence type as XSLT writes it in "as": xs:string?, node()*,
  item()+, element() ... }
function ParseSequenceType(const S: TLandrixXmlUtf8; const Where: string): TLandrixXmlXPathSequenceType;
var
  T: TLandrixXmlUtf8;
  Last: AnsiChar;
begin
  Result.Declared := S <> '';
  Result.Kind := xtkAnyItem;
  Result.AtomicType := xatNone;
  Result.Occurrence := xocOne;
  if not Result.Declared then
  begin
    Result.Occurrence := xocMany;
    Exit;
  end;
  T := S;
  Last := AnsiChar(T[Length(T)]);
  if Last in ['?', '*', '+'] then
  begin
    case Last of
      '?': Result.Occurrence := xocOptional;
      '*': Result.Occurrence := xocMany;
    else
      Result.Occurrence := xocOneOrMore;
    end;
    T := Copy(T, 1, Length(T) - 1);
  end;
  if T = 'item()' then
    Result.Kind := xtkAnyItem
  else if (T = 'node()') or (T = 'element()') or (T = 'attribute()') or (T = 'text()') or (T = 'document-node()') then
    Result.Kind := xtkNode
  else if Copy(T, 1, 3) = 'xs:' then
  begin
    Result.Kind := xtkAtomic;
    Result.AtomicType := LandrixXmlXPathAtomicTypeByName(Copy(T, 4, MaxInt));
    if Result.AtomicType = xatNone then
      SchemaError(Where + ': the type "' + LandrixXmlUtf8ToString(S) + '" is not supported');
  end
  else
    SchemaError(Where + ': the type "' + LandrixXmlUtf8ToString(S) + '" is not supported');
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
end;

destructor TLandrixXmlSchematronRules.Destroy;
begin
  Clear;
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

function TLandrixXmlSchematronRules.Compile(const Text: TLandrixXmlUtf8; Context: TLandrixXmlXPathStaticContext;
  const Where: string): TLandrixXmlXPathExpression;
begin
  try
    Result := TLandrixXmlXPathExpression.Create(Text, Context);
  except
    on E: ELandrixXmlXPathError do
      raise ELandrixXmlXPathError.CreateXPath(E.XPathCode, Where + ': ' + Copy(E.Message, Length(E.XPathCode) + 3,
        MaxInt));
  end;
  FExpressions.Add(Result);
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

procedure TLandrixXmlSchematronRules.Load(Document: TLandrixXmlDocument);
var
  Root, N, F, R, C, P: TLandrixXmlNode;
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
  if AttrOf(Root, 'format') <> '1' then
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
          FFunctionContexts.Add(Ctx);
          DeclareCommon(Ctx);
          Def := TLandrixXmlXPathFunctionDef.Create;
          FOwnedFunctions.Add(Def);
          FFunctions.Add(Def);
          Def.Name := LandrixXmlUtf8ToString(AttrOf(N, 'name'));
          Def.ResultType := ParseSequenceType(AttrOf(N, 'as'), Where);
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
                Def.ParamTypes[I] := ParseSequenceType(AttrOf(F, 'as'), Where);
              end
              else
              begin
                I := Integer(Length(Def.LocalSlots));
                SetLength(Def.LocalSlots, I + 1);
                SetLength(Def.LocalTypes, I + 1);
                SetLength(Def.LocalExpressions, I + 1);
                Def.LocalSlots[I] := Slot;
                Def.LocalTypes[I] := ParseSequenceType(AttrOf(F, 'as'), Where);
                if not Def.LocalTypes[I].Declared then
                  Def.LocalTypes[I].Occurrence := xocMany;
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
              Rule.SourceLine := LandrixXmlUtf8ToString(AttrOf(R, 'line'));
              Rule.ContextText := AttrOf(R, 'context');
              Rule.Context := Compile(ContextExpression(Rule.ContextText, Rule.SourceLine), FContext,
                Rule.SourceLine);
              if UsesCurrent(Rule.Context) then
                raise ELandrixXmlError.CreateCode(xecUnsupported, 'Schematron rules: ' + Rule.SourceLine +
                  ': current() in a rule context is not supported');
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
        else if not (IsRules(N, 'ns')) then
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
  P, R, K, I, J, Node, RuleIndex: Integer;
  Pattern: TLandrixXmlSchematronPattern;
  Rule: TLandrixXmlSchematronRule;
  Check: TLandrixXmlSchematronCheck;
  First: array of Integer;
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
  FResults.Clear;
  FFiredRules.Clear;
  FIncomplete := False;
  Aborted := False;
  Pattern := nil;
  Rule := nil;
  First := nil;
  if FRules.FContext = nil then
    raise ELandrixXmlError.CreateCode(xecInvalidOperation, 'No Schematron rules are loaded');
  E := TLandrixXmlXPathEvaluator.Create(Tree);
  try
    E.Functions := FRules.FFunctions;
    E.SetGlobalCount(FRules.FGlobalCount);
    E.SetFrameSize(FRules.FContext.VariableCount);
    for I := 0 to Integer(FRules.FGlobals.Count) - 1 do
      E.BindLazy(TVariable(FRules.FGlobals[I]).Slot, TVariable(FRules.FGlobals[I]).Expression, 0);
    SetLength(First, Tree.Count);
    for P := 0 to FRules.PatternCount - 1 do
    begin
      if Aborted then
        Break;
      Pattern := FRules.Patterns[P];
      { the nodes of each rule's context; the first rule wins }
      for Node := 0 to Tree.Count - 1 do
        First[Node] := -1;
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
        for K := 0 to Nodes.Count - 1 do
          if Nodes.Items[K].Kind = xikNode then
            First[Nodes.Items[K].Node] := R;
      end;
      Nodes := LandrixXmlXPathEmpty;
      if Aborted then
        Break;
      for Node := 0 to Tree.Count - 1 do
      begin
        RuleIndex := First[Node];
        if RuleIndex < 0 then
          Continue;
        Rule := TLandrixXmlSchematronRule(Pattern.Rules[RuleIndex]);
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
      end;
    end;
  finally
    E.Free;
  end;
  Result := not FIncomplete;
  for I := 0 to Integer(FResults.Count) - 1 do
    if (Results[I].Kind <> xsrDynamicError) and (Results[I].Flag <> 'warning') and (Results[I].Flag <> 'information') then
      Result := False;
end;

function TLandrixXmlSchematronValidator.ValidateFile(const FileName: string): Boolean;
var
  Tree: TLandrixXmlXPathTree;
begin
  Tree := TLandrixXmlXPathTree.Create;
  try
    Tree.LoadFromFile(FileName);
    Result := ValidateTree(Tree);
  finally
    Tree.Free;
  end;
end;

function TLandrixXmlSchematronValidator.ValidateDocument(Document: TLandrixXmlDocument): Boolean;
var
  Tree: TLandrixXmlXPathTree;
begin
  Tree := TLandrixXmlXPathTree.Create;
  try
    Tree.LoadFromDocument(Document);
    Result := ValidateTree(Tree);
  finally
    Tree.Free;
  end;
end;

end.
