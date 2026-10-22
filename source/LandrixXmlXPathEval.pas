{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Evaluates compiled XPath expressions (LandrixXmlXPath) on a tree
  (LandrixXmlXPathTree) as Saxon HE does without a schema: every node's
  typed value is xs:untypedAtomic, which becomes xs:double in arithmetic
  and in comparisons with numbers and xs:string in comparisons with
  strings; decimal division follows Saxon's scale rule
  (LandrixXmlDecimal); doubles are computed in software (LandrixXmlDouble)
  and written as Saxon writes them; strings are compared by code point;
  fn:upper-case and fn:lower-case map as Saxon does (U+00DF becomes SS;
  the table is generated from Saxon).

  Like Saxon the evaluator does not evaluate what it does not need: "and"
  and "or" decide on either operand (an error in one operand does not
  matter if the other decides), variables are evaluated when first used,
  "if" evaluates one branch, "some" and "every" stop at the first decisive
  item. Dynamic errors raise ELandrixXmlXPathError with the W3C code
  (FORG0001 invalid cast, XPTY0004 type error, FOAR0001 division by zero,
  FORX0003 regex matching the empty string, ...).

  Variables: the slots of the static context are bound before an
  expression is evaluated (BindValue, or BindLazy for an expression that
  is evaluated on first use); slots below GlobalCount are shared by all
  frames (global variables), the others belong to the current frame (the
  variables of a Schematron rule, or the parameters and local variables
  of a user function). for, some and every use slots of their own.

  Not supported (a dynamic error XPST0017 or FOER0000, never a wrong
  value): xs:float values (no rule set uses them), date and time
  arithmetic, casts between xs:date, xs:dateTime and xs:time, comparing
  dates with and without time zone (Saxon uses the machine's implicit
  time zone), ranges ("to") of more than 10,000,000 items (FOAR0002;
  Saxon would stream them), the year 0000 (XML Schema 1.0). Unlike Saxon
  the binding sequence of for, some and every is evaluated before the
  first item is used, so an error in a later item is raised even if an
  earlier one decides. Errors of the number units (an exponent out of
  range) are raised as FOAR0002 or FOCA0002. Dates follow XML Schema 1.0
  as LandrixXmlXsdTypes reads them (time zones up to 14:00, any number of
  fraction digits), where Saxon accepts more and keeps nanoseconds.
  fn:round and fn:round-half-to-even round large integers exactly
  (Saxon goes through xs:double there).

  An evaluator keeps the value of every subexpression that depends
  neither on the focus (context item, position, size) nor on current()
  nor on a variable other than a global one, such as an absolute path or
  count(//x): it is computed once per evaluator, as the rule sets ask for
  the same totals on every line of an invoice. Binding a global variable
  or SetGlobalCount drops the kept values; ClearCache too, which is needed
  only when the tree is loaded again while the evaluator lives.

  EvaluatePattern evaluates a path as the nodes an XSLT match pattern
  matches: a dynamic error in a predicate of one of its steps means that
  the item does not match (XSLT 3.0, 5.5.4), so the other items are kept.
  Later predicates that may use the position count as in Saxon (see
  ApplyPredicates): a[p][1] is still the first item when it comes before
  the failing one, a[p][last()] matches nothing. Saxon may stop early for
  position(): a[p][position() < 3] can still match before the failure
  there, here it does not. In a union a node one branch failed on does
  not match a later branch (Saxon tries them in order); only a failure on
  the branch's last step counts for that, not one on a step above it.
  Errors inside such a predicate (in a nested path) are not caught below
  it. Not caught at all: a circular variable (XTDE0640) and what is not
  supported (FOER0000, XPST0017), which must stay visible. The path is
  evaluated as given: a Schematron context must already be written as
  the nodes it selects (//a for the pattern a). }

unit LandrixXmlXPathEval;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  Classes,
  LandrixXmlBase,
  LandrixXmlDecimal,
  LandrixXmlDouble,
  Contnrs,
  LandrixXmlRegex,
  LandrixXmlUnicode,
  LandrixXmlXsdTypes,
  LandrixXmlXPathTree,
  LandrixXmlXPath;

type
  TLandrixXmlXPathItemKind = (xikNode, xikUntypedAtomic, xikString, xikAnyUri, xikBoolean, xikInteger,
    xikDecimal, xikDouble, xikDate, xikDateTime, xikTime);

  { An item: a node of the tree (Node) or an atomic value. Internal, public
    because the evaluator's records need it. }
  TLandrixXmlXPathItem = record
    Kind: TLandrixXmlXPathItemKind;
    Node: Integer;
    { strings, untypedAtomic, anyURI, and the lexical form of dates }
    Text: TLandrixXmlUtf8;
    Decimal: TLandrixXmlDecimal;
    DoubleValue: TLandrixXmlDouble;
    BooleanValue: Boolean;
    DateTime: TLandrixXmlXsdDateTime;
  end;
  TLandrixXmlXPathItems = array of TLandrixXmlXPathItem;

  TLandrixXmlXPathSequence = record
    Items: TLandrixXmlXPathItems;
    Count: Integer;
  end;

  { The declared type of a variable, parameter or function result. }
  TLandrixXmlXPathOccurrence = (xocOne, xocOptional, xocMany, xocOneOrMore);
  TLandrixXmlXPathTypeKind = (xtkAnyItem, xtkNode, xtkAtomic);
  TLandrixXmlXPathSequenceType = record
    Kind: TLandrixXmlXPathTypeKind;
    AtomicType: TLandrixXmlXPathAtomicType;
    Occurrence: TLandrixXmlXPathOccurrence;
    { False: no "as", anything goes }
    Declared: Boolean;
  end;

  TLandrixXmlXPathSlotState = (xssUnbound, xssValue, xssLazy, xssEvaluating, xssError);

  TLandrixXmlXPathSlot = record
    State: TLandrixXmlXPathSlotState;
    Value: TLandrixXmlXPathSequence;
    Expression: TLandrixXmlXPathExpression;
    ContextNode: Integer;
    ErrorCode: string;
    ErrorMessage: string;
    { the declared type the value is converted to (xsl:variable as=) }
    DeclaredType: TLandrixXmlXPathSequenceType;
  end;
  TLandrixXmlXPathSlots = array of TLandrixXmlXPathSlot;

  { A user function: parameters and local variables are slots of the
    static context its expressions were compiled with (whose first
    GlobalCount variables are the globals); locals are evaluated lazily,
    the body gives the result. Owned by the caller. }
  TLandrixXmlXPathFunctionDef = class
  public
    ParamSlots: array of Integer;
    ParamTypes: array of TLandrixXmlXPathSequenceType;
    LocalSlots: array of Integer;
    LocalExpressions: array of TLandrixXmlXPathExpression;
    LocalTypes: array of TLandrixXmlXPathSequenceType;
    Body: TLandrixXmlXPathExpression;
    ResultType: TLandrixXmlXPathSequenceType;
    { the number of variables of the function's static context }
    FrameSize: Integer;
    Name: string;
  end;

  { The result of Evaluate. }
  TLandrixXmlXPathResult = class
  private
    FItems: TLandrixXmlXPathSequence;
    FTree: TLandrixXmlXPathTree;
    function GetCount: Integer;
    function GetKind(Index: Integer): TLandrixXmlXPathItemKind;
    function GetNode(Index: Integer): Integer;
  public
    property Count: Integer read GetCount;
    property Kind[Index: Integer]: TLandrixXmlXPathItemKind read GetKind;
    { the node of a node item (an index into the tree), -1 for atomic values }
    property Node[Index: Integer]: Integer read GetNode;
    { the string value of the item (fn:string) }
    function StringValueUtf8(Index: Integer): TLandrixXmlUtf8;
    { the XPath type name: xs:string, xs:decimal, ...; node() for nodes }
    function TypeName(Index: Integer): string;
    { the effective boolean value of the whole result }
    function AsBoolean: Boolean;
  end;

  TLandrixXmlXPathEvaluator = class
  private
    FTree: TLandrixXmlXPathTree;
    FGlobalCount: Integer;
    FGlobals: TLandrixXmlXPathSlots;
    FFrame: TLandrixXmlXPathSlots;
    { slots of for, some and every: a stack, one block per expression being evaluated }
    FLocals: array of TLandrixXmlXPathSequence;
    FLocalTop: Integer;
    FFunctions: TList;
    FCurrentNode: Integer;
    FDepth: Integer;
    FMaxDepth: Integer;
    { compiled patterns: flags + #0 + pattern (UTF-8) and the regex }
    FRegexKeys: TLandrixXmlUtf8Array;
    FRegexes: TObjectList;
    { the expression being evaluated and the base of its local slots }
    FExpr: TLandrixXmlXPathExpression;
    FNodes: TLandrixXmlXPathAstNodes;
    FLocalBase: Integer;
    { kept values of context-free subexpressions: one entry per expression
      (owned by FCaches, found by FCacheTable), FCache that of FExpr }
    FCaches: TObjectList;
    FCacheTable: array of TObject;
    FCache: TObject;
    { the node being computed for its entry, so that Eval does not look again }
    FBypass: Integer;
    { EnterExpression calls not yet left }
    FNesting: Integer;
    { EvaluatePattern: the predicates of the steps being evaluated drop the
      items they fail on; FFinal while the last step of a branch is
      evaluated, whose failed items FFailed lists (a later branch of a
      union must not match them) }
    FPattern: Boolean;
    FFinal: Boolean;
    FFailed: array of Integer;
    FFailedCount: Integer;
    { the first node from which a pattern's positions are still unknown
      after the predicates evaluated so far (MaxInt if none) }
    FMinFailed: Integer;
    procedure CutAfterFailure(var S: TLandrixXmlXPathSequence; FailAt: Integer; All, Final: Boolean);
    procedure AddFailed(Node: Integer);
    function WithoutFailed(const S: TLandrixXmlXPathSequence; First, Last: Integer): TLandrixXmlXPathSequence;
    function FindCache(Expr: TLandrixXmlXPathExpression): TObject;
    function CachedEval(Index: Integer; Context: Integer; Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    procedure DropCachedValues;
    { EvaluateSequence without the copy, for read-only use }
    function EvaluateShared(Expr: TLandrixXmlXPathExpression; ContextNode: Integer): TLandrixXmlXPathSequence;
    procedure EnterExpression(Expr: TLandrixXmlXPathExpression; out SavedExpr: TLandrixXmlXPathExpression;
      out SavedBase: Integer);
    procedure LeaveExpression(SavedExpr: TLandrixXmlXPathExpression; SavedBase: Integer);
    function SlotRef(Slot: Integer): Pointer;
    function ReadVariable(Slot: Integer): TLandrixXmlXPathSequence;
    procedure WriteLocal(Slot: Integer; const Value: TLandrixXmlXPathSequence);
    function Eval(Index: Integer; Context: Integer; Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    function EvalStep(Index: Integer; Node: Integer; Axis: TLandrixXmlXPathAxis): TLandrixXmlXPathSequence;
    function EvalPath(Index: Integer; Context, Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    function ApplyPredicates(const Predicates: array of Integer;
      const Input: TLandrixXmlXPathSequence; InputFailedAt: Integer): TLandrixXmlXPathSequence;
    function EvalQuantified(Index, Binding: Integer; Context, Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence; Kind: TLandrixXmlXPathAstKind;
      var Output: TLandrixXmlXPathSequence): Boolean;
    function CallFunction(Index: Integer; Context, Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    function CallUser(Def: TLandrixXmlXPathFunctionDef; const Args: array of TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    function Regex(const Pattern, Flags: TLandrixXmlUtf8): TLandrixXmlRegex;
    function StringOf(const Item: TLandrixXmlXPathItem): TLandrixXmlUtf8;
    function Atomize(const S: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    function ConvertTo(const S: TLandrixXmlXPathSequence; const T: TLandrixXmlXPathSequenceType;
      const FunctionName: string): TLandrixXmlXPathSequence;
  public
    { The tree is not owned. }
    constructor Create(Tree: TLandrixXmlXPathTree);
    destructor Destroy; override;
    { Evaluates Expr with the node ContextNode as context item (position 1,
      size 1). The caller frees the result. }
    function Evaluate(Expr: TLandrixXmlXPathExpression; ContextNode: Integer): TLandrixXmlXPathResult;
    function EvaluateBoolean(Expr: TLandrixXmlXPathExpression; ContextNode: Integer): Boolean;
    { the string values of the items joined with spaces (xsl:value-of) }
    function EvaluateString(Expr: TLandrixXmlXPathExpression; ContextNode: Integer): TLandrixXmlUtf8;
    function EvaluateSequence(Expr: TLandrixXmlXPathExpression; ContextNode: Integer): TLandrixXmlXPathSequence;
    { EvaluateSequence as an XSLT match pattern (see the unit comment); Expr
      is the path of the matched nodes (//a for the pattern a) }
    function EvaluatePattern(Expr: TLandrixXmlXPathExpression; ContextNode: Integer): TLandrixXmlXPathSequence;
    { Variables: slots below GlobalCount are global; the others belong to
      the current frame. Setting GlobalCount or FrameSize unbinds the slots
      concerned. }
    procedure SetGlobalCount(Count: Integer);
    procedure SetFrameSize(Size: Integer);
    procedure BindValue(Slot: Integer; const Value: TLandrixXmlXPathSequence);
    procedure BindString(Slot: Integer; const Value: TLandrixXmlUtf8);
    { evaluated on first use with ContextNode as context item }
    procedure BindLazy(Slot: Integer; Expr: TLandrixXmlXPathExpression; ContextNode: Integer);
    procedure UnbindFrame;
    { forgets the kept values of context-free subexpressions (see the unit
      comment); needed when the tree changes while the evaluator lives }
    procedure ClearCache;
    { user functions (TLandrixXmlXPathFunctionDef) by their index in the
      static context; not owned }
    property Functions: TList read FFunctions write FFunctions;
    { the node fn:current() returns (the context node of a Schematron rule) }
    property CurrentNode: Integer read FCurrentNode write FCurrentNode;
    property Tree: TLandrixXmlXPathTree read FTree;
    { the maximum nesting of user function calls (default 500) }
    property MaxDepth: Integer read FMaxDepth write FMaxDepth;
  end;

{ The empty sequence and single items. }
function LandrixXmlXPathEmpty: TLandrixXmlXPathSequence;
function LandrixXmlXPathStringItem(const S: TLandrixXmlUtf8): TLandrixXmlXPathSequence;
function LandrixXmlXPathNodeItem(Node: Integer): TLandrixXmlXPathSequence;
procedure LandrixXmlXPathAppend(var S: TLandrixXmlXPathSequence; const Item: TLandrixXmlXPathItem);

implementation

{$I LandrixXmlCaseData.inc}

type
  PSlot = ^TLandrixXmlXPathSlot;

  { The kept values of one expression: Flags marks the outermost
    context-free subexpressions worth keeping. }
  TExpressionCache = class
  public
    Expression: TLandrixXmlXPathExpression;
    Serial: Int64;
    Flags: array of Boolean;
    Have: array of Boolean;
    Values: array of TLandrixXmlXPathSequence;
    { a child step whose predicates do not depend on the position: after
      descendant-or-self::node() ("//") it is evaluated as descendant }
    Fuse: array of Boolean;
  end;

  TDependency = (xdFocus, xdOther);
  TDependencies = set of TDependency;

procedure Fail(const Code, Msg: string);
begin
  raise ELandrixXmlXPathError.CreateXPath(Code, Msg);
end;

{ --- sequences ---------------------------------------------------------- }

function LandrixXmlXPathEmpty: TLandrixXmlXPathSequence;
begin
  Result.Items := nil;
  Result.Count := 0;
end;

procedure LandrixXmlXPathAppend(var S: TLandrixXmlXPathSequence; const Item: TLandrixXmlXPathItem);
begin
  if S.Count = Length(S.Items) then
    SetLength(S.Items, 2 * S.Count + 4);
  S.Items[S.Count] := Item;
  Inc(S.Count);
end;

procedure AppendAll(var S: TLandrixXmlXPathSequence; const T: TLandrixXmlXPathSequence);
var
  I: Integer;
begin
  for I := 0 to T.Count - 1 do
    LandrixXmlXPathAppend(S, T.Items[I]);
end;

procedure InitItem(out Item: TLandrixXmlXPathItem; Kind: TLandrixXmlXPathItemKind);
begin
  Item.Kind := Kind;
  Item.Node := -1;
  Item.Text := '';
  Item.Decimal := LandrixXmlDecimalZero;
  Item.DoubleValue := LandrixXmlDoubleZero(False);
  Item.BooleanValue := False;
  Item.DateTime.Year := 0;
  Item.DateTime.Month := 0;
  Item.DateTime.Day := 0;
  Item.DateTime.Hour := 0;
  Item.DateTime.Minute := 0;
  Item.DateTime.Second := LandrixXmlDecimalZero;
  Item.DateTime.HasTimeZone := False;
  Item.DateTime.TimeZone := 0;
end;

function SingleSeq(const Item: TLandrixXmlXPathItem): TLandrixXmlXPathSequence;
begin
  Result.Items := nil;
  SetLength(Result.Items, 1);
  Result.Items[0] := Item;
  Result.Count := 1;
end;

function LandrixXmlXPathNodeItem(Node: Integer): TLandrixXmlXPathSequence;
var
  Item: TLandrixXmlXPathItem;
begin
  InitItem(Item, xikNode);
  Item.Node := Node;
  Result := SingleSeq(Item);
end;

function StringItem(Kind: TLandrixXmlXPathItemKind; const S: TLandrixXmlUtf8): TLandrixXmlXPathItem;
begin
  InitItem(Result, Kind);
  Result.Text := S;
end;

function LandrixXmlXPathStringItem(const S: TLandrixXmlUtf8): TLandrixXmlXPathSequence;
begin
  Result := SingleSeq(StringItem(xikString, S));
end;

function BooleanItem(B: Boolean): TLandrixXmlXPathItem;
begin
  InitItem(Result, xikBoolean);
  Result.BooleanValue := B;
end;

function BooleanSeq(B: Boolean): TLandrixXmlXPathSequence;
begin
  Result := SingleSeq(BooleanItem(B));
end;

function IntegerItem(const D: TLandrixXmlDecimal): TLandrixXmlXPathItem;
begin
  InitItem(Result, xikInteger);
  Result.Decimal := D;
end;

function IntegerItemOf(Value: Int64): TLandrixXmlXPathItem;
begin
  Result := IntegerItem(LandrixXmlDecimalFromInt64(Value));
end;

function DecimalItem(const D: TLandrixXmlDecimal): TLandrixXmlXPathItem;
begin
  InitItem(Result, xikDecimal);
  Result.Decimal := D;
end;

function DoubleItem(const D: TLandrixXmlDouble): TLandrixXmlXPathItem;
begin
  InitItem(Result, xikDouble);
  Result.DoubleValue := D;
end;

function IsNumeric(Kind: TLandrixXmlXPathItemKind): Boolean;
begin
  Result := Kind in [xikInteger, xikDecimal, xikDouble];
end;

function IsStringLike(Kind: TLandrixXmlXPathItemKind): Boolean;
begin
  Result := Kind in [xikString, xikUntypedAtomic, xikAnyUri];
end;

function KindName(Kind: TLandrixXmlXPathItemKind): string;
begin
  case Kind of
    xikNode: Result := 'node()';
    xikUntypedAtomic: Result := 'xs:untypedAtomic';
    xikString: Result := 'xs:string';
    xikAnyUri: Result := 'xs:anyURI';
    xikBoolean: Result := 'xs:boolean';
    xikInteger: Result := 'xs:integer';
    xikDecimal: Result := 'xs:decimal';
    xikDouble: Result := 'xs:double';
    xikDate: Result := 'xs:date';
    xikDateTime: Result := 'xs:dateTime';
  else
    Result := 'xs:time';
  end;
end;

{ --- string helpers (code points) ----------------------------------------- }

function CodePointLength(const S: TLandrixXmlUtf8): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Length(S) do
    if (Ord(S[I]) and $C0) <> $80 then
      Inc(Result);
end;

{ The byte position (1-based) of code point N (1-based) in S; Length + 1
  after the end. }
function BytePosition(const S: TLandrixXmlUtf8; N: Integer): Integer;
var
  K: Integer;
begin
  Result := 1;
  K := 1;
  while (Result <= Length(S)) and (K < N) do
  begin
    Inc(Result);
    while (Result <= Length(S)) and ((Ord(S[Result]) and $C0) = $80) do
      Inc(Result);
    Inc(K);
  end;
end;

function NormalizeSpace(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
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

function Trimmed(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  A, B: Integer;
begin
  A := 1;
  B := Length(S);
  while (A <= B) and (S[A] in [' ', #9, #10, #13]) do
    Inc(A);
  while (B >= A) and (S[B] in [' ', #9, #10, #13]) do
    Dec(B);
  Result := Copy(S, A, B - A + 1);
end;

function MapCase(const S: TLandrixXmlUtf8; Upper: Boolean): TLandrixXmlUtf8;
var
  CPs: TLandrixXmlCodePoints;
  I, Lo, Hi, Mid, Key, Count, Start, Stop: Integer;
  Buf: TLandrixXmlUtf8;
  Ascii: Boolean;
begin
  CPs := nil;
  { ASCII only: no table }
  Ascii := True;
  for I := 1 to Length(S) do
    if Ord(S[I]) >= $80 then
    begin
      Ascii := False;
      Break;
    end;
  if Ascii then
  begin
    Result := S;
    for I := 1 to Length(Result) do
      if Upper and (Result[I] in ['a'..'z']) then
        Result[I] := AnsiChar(Ord(Result[I]) - 32)
      else if not Upper and (Result[I] in ['A'..'Z']) then
        Result[I] := AnsiChar(Ord(Result[I]) + 32);
    Exit;
  end;
  CPs := LandrixXmlUtf8ToCodePoints(S);
  Result := '';
  if Upper then
    Count := UpperCaseCount
  else
    Count := LowerCaseCount;
  for I := 0 to Integer(Length(CPs)) - 1 do
  begin
    Lo := 0;
    Hi := Count - 1;
    Mid := -1;
    while Lo <= Hi do
    begin
      Mid := (Lo + Hi) div 2;
      if Upper then
        Key := UpperCaseKeys[Mid]
      else
        Key := LowerCaseKeys[Mid];
      if Key = CPs[I] then
        Break;
      if Key < CPs[I] then
        Lo := Mid + 1
      else
        Hi := Mid - 1;
      Mid := -1;
    end;
    if Mid < 0 then
    begin
      Buf := '';
      SetLength(Buf, 4);
      SetLength(Buf, LandrixXmlEncodeUtf8(Cardinal(CPs[I]), PAnsiChar(Buf)));
      Result := Result + Buf;
    end
    else
    begin
      if Upper then
      begin
        Start := UpperCaseStarts[Mid];
        Stop := UpperCaseStarts[Mid + 1];
      end
      else
      begin
        Start := LowerCaseStarts[Mid];
        Stop := LowerCaseStarts[Mid + 1];
      end;
      Buf := '';
      SetLength(Buf, Stop - Start);
      for Key := Start to Stop - 1 do
        if Upper then
          Buf[Key - Start + 1] := AnsiChar(UpperCasePool[Key])
        else
          Buf[Key - Start + 1] := AnsiChar(LowerCasePool[Key]);
      Result := Result + Buf;
    end;
  end;
end;

{ --- TLandrixXmlXPathResult ------------------------------------------------ }

function TLandrixXmlXPathResult.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TLandrixXmlXPathResult.GetKind(Index: Integer): TLandrixXmlXPathItemKind;
begin
  Result := FItems.Items[Index].Kind;
end;

function TLandrixXmlXPathResult.GetNode(Index: Integer): Integer;
begin
  Result := FItems.Items[Index].Node;
end;

function TLandrixXmlXPathResult.TypeName(Index: Integer): string;
begin
  Result := KindName(FItems.Items[Index].Kind);
end;

{$I LandrixXmlXPathCast.inc}

function TLandrixXmlXPathResult.StringValueUtf8(Index: Integer): TLandrixXmlUtf8;
begin
  if FItems.Items[Index].Kind = xikNode then
    Result := FTree.StringValueUtf8(FItems.Items[Index].Node)
  else
    Result := AtomicString(FItems.Items[Index]);
end;

function TLandrixXmlXPathResult.AsBoolean: Boolean;
begin
  Result := SequenceBoolean(FItems);
end;

{ --- TLandrixXmlXPathEvaluator ---------------------------------------------- }

constructor TLandrixXmlXPathEvaluator.Create(Tree: TLandrixXmlXPathTree);
begin
  inherited Create;
  FTree := Tree;
  FMaxDepth := 500;
  FCurrentNode := -1;
  FRegexes := TObjectList.Create(True);
  FCaches := TObjectList.Create(True);
  FBypass := -1;
end;

destructor TLandrixXmlXPathEvaluator.Destroy;
begin
  FCaches.Free;
  FRegexes.Free;
  inherited Destroy;
end;

{ --- kept values of context-free subexpressions ------------------------- }

const
  { more expressions than that in one evaluator: start again }
  MaxCachedExpressions = 4096;

const
  ContextFunctions = [xfnString, xfnStringLength, xfnNormalizeSpace, xfnNumber, xfnName, xfnLocalName,
    xfnNamespaceUri, xfnRoot];

{ What the value of node Index depends on besides the tree and the global
  variables; Free receives the nodes that depend on neither. }
function Dependencies(const Nodes: TLandrixXmlXPathAstNodes; Index, GlobalCount, FirstLocalSlot: Integer;
  var Free: array of Boolean): TDependencies;
var
  I, First: Integer;
  Id: TLandrixXmlXPathFunctionId;
  Deps: TDependencies;

  { predicates and later steps have a focus of their own }
  procedure Inner(Child: Integer);
  begin
    Deps := Deps + Dependencies(Nodes, Child, GlobalCount, FirstLocalSlot, Free) * [xdOther];
  end;

begin
  Deps := [];
  case Nodes[Index].Kind of
    xakContextItem, xakRoot:
      Deps := [xdFocus];
    xakStep:
      begin
        Deps := [xdFocus];
        for I := 0 to Integer(High(Nodes[Index].Predicates)) do
          Inner(Nodes[Index].Predicates[I]);
      end;
    xakPath:
      begin
        First := 0;
        if not Nodes[Index].RootStart then
        begin
          Deps := Dependencies(Nodes, Nodes[Index].Children[0], GlobalCount, FirstLocalSlot, Free);
          First := 1;
        end
        else
          { "/" needs a node as context; the tree has one root }
          Deps := [];
        for I := First to Integer(High(Nodes[Index].Children)) do
          Inner(Nodes[Index].Children[I]);
      end;
    xakFilter:
      begin
        Deps := Dependencies(Nodes, Nodes[Index].Children[0], GlobalCount, FirstLocalSlot, Free);
        for I := 0 to Integer(High(Nodes[Index].Predicates)) do
          Inner(Nodes[Index].Predicates[I]);
      end;
    xakVariable:
      { global: a slot of the static context below GlobalCount; the slots
        from FirstLocalSlot on are those of for, some and every }
      if (Nodes[Index].Slot >= GlobalCount) or (Nodes[Index].Slot >= FirstLocalSlot) then
        Deps := [xdOther];
  else
    for I := 0 to Integer(High(Nodes[Index].Children)) do
      Deps := Deps + Dependencies(Nodes, Nodes[Index].Children[I], GlobalCount, FirstLocalSlot, Free);
    for I := 0 to Integer(High(Nodes[Index].Predicates)) do
      Inner(Nodes[Index].Predicates[I]);
    if (Nodes[Index].Kind = xakFunction) and (Nodes[Index].Op >= 0) then
    begin
      Id := TLandrixXmlXPathFunctionId(Nodes[Index].Op);
      if (Id = xfnPosition) or (Id = xfnLast) or ((Id in ContextFunctions) and (Length(Nodes[Index].Children) = 0)) then
        Include(Deps, xdFocus)
      else if Id = xfnCurrent then
        Include(Deps, xdOther);
    end;
  end;
  Free[Index] := Deps = [];
  Result := Deps;
end;

{ True if the predicate Index may depend on the position: it may be a
  number, or it calls position() or last(). }
function MayBePositional(const Nodes: TLandrixXmlXPathAstNodes; Index: Integer): Boolean;
const
  NotNumeric = [xfnNot, xfnTrue, xfnFalse, xfnBoolean, xfnExists, xfnEmpty, xfnContains, xfnStartsWith,
    xfnEndsWith, xfnMatches, xfnString, xfnNormalizeSpace, xfnConcat, xfnUpperCase, xfnLowerCase, xfnName,
    xfnLocalName];

  function UsesPosition(I: Integer): Boolean;
  var
    J: Integer;
  begin
    Result := (Nodes[I].Kind = xakFunction) and (Nodes[I].Op >= 0) and
      (TLandrixXmlXPathFunctionId(Nodes[I].Op) in [xfnPosition, xfnLast]);
    J := 0;
    while not Result and (J < Length(Nodes[I].Children)) do
    begin
      Result := UsesPosition(Nodes[I].Children[J]);
      Inc(J);
    end;
    J := 0;
    while not Result and (J < Length(Nodes[I].Predicates)) do
    begin
      Result := UsesPosition(Nodes[I].Predicates[J]);
      Inc(J);
    end;
  end;

begin
  case Nodes[Index].Kind of
    xakGeneralCompare, xakValueCompare, xakAnd, xakOr, xakString, xakCastable, xakUnion, xakSome, xakEvery,
    xakStep:
      Result := False;
    xakPath:
      Result := Nodes[Nodes[Index].Children[Integer(High(Nodes[Index].Children))]].Kind <> xakStep;
    xakFunction:
      Result := (Nodes[Index].Op < 0) or not (TLandrixXmlXPathFunctionId(Nodes[Index].Op) in NotNumeric);
  else
    Result := True;
  end;
  if not Result then
    Result := UsesPosition(Index);
end;

{ Marks the outermost free nodes that are worth keeping. }
procedure MarkOutermost(const Nodes: TLandrixXmlXPathAstNodes; Index: Integer; ParentFree: Boolean;
  const Free: array of Boolean; var Flags: array of Boolean);
var
  I: Integer;
begin
  Flags[Index] := Free[Index] and not ParentFree and not (Nodes[Index].Kind in [xakEmpty, xakString, xakInteger,
    xakDecimal, xakDouble, xakVariable]);
  for I := 0 to Integer(High(Nodes[Index].Children)) do
    MarkOutermost(Nodes, Nodes[Index].Children[I], Free[Index], Free, Flags);
  for I := 0 to Integer(High(Nodes[Index].Predicates)) do
    MarkOutermost(Nodes, Nodes[Index].Predicates[I], Free[Index], Free, Flags);
end;

function TLandrixXmlXPathEvaluator.FindCache(Expr: TLandrixXmlXPathExpression): TObject;
var
  H, Mask, I, J, Count: Integer;
  C: TExpressionCache;
  Free: array of Boolean;
begin
  Result := nil;
  if (Expr = nil) or (Expr.NodeCount = 0) then
    Exit;
  if Length(FCacheTable) = 0 then
    SetLength(FCacheTable, 64);
  Mask := Integer(Length(FCacheTable)) - 1;
  H := Integer(Expr.Serial and Mask);
  while FCacheTable[H] <> nil do
  begin
    C := TExpressionCache(FCacheTable[H]);
    if (C.Expression = Expr) and (C.Serial = Expr.Serial) then
    begin
      Result := C;
      Exit;
    end;
    H := (H + 1) and Mask;
  end;
  if FCaches.Count >= MaxCachedExpressions then
  begin
    { inside an evaluation an entry may be in use: no new one }
    if FNesting > 1 then
      Exit;
    FCaches.Clear;
    FCacheTable := nil;
    SetLength(FCacheTable, 64);
    Mask := 63;
    H := Integer(Expr.Serial and Mask);
  end;
  C := TExpressionCache.Create;
  FCaches.Add(C);
  C.Expression := Expr;
  C.Serial := Expr.Serial;
  Count := Expr.NodeCount;
  Free := nil;
  SetLength(Free, Count);
  SetLength(C.Flags, Count);
  SetLength(C.Have, Count);
  SetLength(C.Values, Count);
  for I := 0 to Count - 1 do
  begin
    Free[I] := False;
    C.Flags[I] := False;
    C.Have[I] := False;
  end;
  Dependencies(Expr.NodeArray, Expr.Root, FGlobalCount, Expr.FirstLocalSlot, Free);
  MarkOutermost(Expr.NodeArray, Expr.Root, False, Free, C.Flags);
  SetLength(C.Fuse, Count);
  for I := 0 to Count - 1 do
  begin
    C.Fuse[I] := (Expr.NodeArray[I].Kind = xakStep) and (Expr.NodeArray[I].Axis = xaxChild);
    J := 0;
    while C.Fuse[I] and (J < Length(Expr.NodeArray[I].Predicates)) do
    begin
      C.Fuse[I] := not MayBePositional(Expr.NodeArray, Expr.NodeArray[I].Predicates[J]);
      Inc(J);
    end;
  end;
  FCacheTable[H] := C;
  Result := C;
  { at most half full; the entries of a freed expression stay (an
    expression at the same address has another serial) }
  if 2 * FCaches.Count > Length(FCacheTable) then
  begin
    Count := 2 * Integer(Length(FCacheTable));
    FCacheTable := nil;
    SetLength(FCacheTable, Count);
    Mask := Count - 1;
    for I := 0 to Integer(FCaches.Count) - 1 do
    begin
      H := Integer(TExpressionCache(FCaches[I]).Serial and Mask);
      while FCacheTable[H] <> nil do
        H := (H + 1) and Mask;
      FCacheTable[H] := FCaches[I];
    end;
  end;
end;

procedure TLandrixXmlXPathEvaluator.DropCachedValues;
var
  I, J: Integer;
  C: TExpressionCache;
begin
  for I := 0 to Integer(FCaches.Count) - 1 do
  begin
    C := TExpressionCache(FCaches[I]);
    for J := 0 to Integer(Length(C.Have)) - 1 do
      if C.Have[J] then
      begin
        C.Have[J] := False;
        C.Values[J] := LandrixXmlXPathEmpty;
      end;
  end;
end;

procedure TLandrixXmlXPathEvaluator.ClearCache;
begin
  DropCachedValues;
end;

function TLandrixXmlXPathEvaluator.CachedEval(Index: Integer; Context: Integer; Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
var
  C: TExpressionCache;
begin
  C := TExpressionCache(FCache);
  if C.Have[Index] then
  begin
    Result := C.Values[Index];
    Exit;
  end;
  FBypass := Index;
  Result := Eval(Index, Context, Position, Size, ContextItem);
  { no spare capacity: whoever appends to the value gets a copy }
  if Length(Result.Items) > Result.Count then
    SetLength(Result.Items, Result.Count);
  C.Values[Index] := Result;
  C.Have[Index] := True;
end;

procedure ClearSlot(var Slot: TLandrixXmlXPathSlot);
begin
  Slot.State := xssUnbound;
  Slot.Value := LandrixXmlXPathEmpty;
  Slot.Expression := nil;
  Slot.ContextNode := -1;
  Slot.ErrorCode := '';
  Slot.ErrorMessage := '';
  Slot.DeclaredType.Declared := False;
end;

procedure TLandrixXmlXPathEvaluator.SetGlobalCount(Count: Integer);
var
  I: Integer;
begin
  { what is context-free depends on which slots are global }
  FGlobalCount := Count;
  FCaches.Clear;
  FCacheTable := nil;
  FCache := FindCache(FExpr);
  SetLength(FGlobals, Count);
  for I := 0 to Count - 1 do
    ClearSlot(FGlobals[I]);
end;

procedure TLandrixXmlXPathEvaluator.SetFrameSize(Size: Integer);
var
  I: Integer;
begin
  SetLength(FFrame, Size);
  for I := 0 to Size - 1 do
    ClearSlot(FFrame[I]);
end;

procedure TLandrixXmlXPathEvaluator.UnbindFrame;
var
  I: Integer;
begin
  for I := 0 to Integer(Length(FFrame)) - 1 do
    ClearSlot(FFrame[I]);
end;

function TLandrixXmlXPathEvaluator.SlotRef(Slot: Integer): Pointer;
begin
  if Slot < FGlobalCount then
    Result := @FGlobals[Slot]
  else
  begin
    if Slot >= Length(FFrame) then
      Fail('XPDY0002', 'variable slot ' + IntToStr(Slot) + ' is not bound');
    Result := @FFrame[Slot];
  end;
end;

procedure TLandrixXmlXPathEvaluator.BindValue(Slot: Integer; const Value: TLandrixXmlXPathSequence);
var
  P: PSlot;
begin
  P := SlotRef(Slot);
  ClearSlot(P^);
  P^.State := xssValue;
  P^.Value := Value;
  if Slot < FGlobalCount then
    DropCachedValues;
end;

procedure TLandrixXmlXPathEvaluator.BindString(Slot: Integer; const Value: TLandrixXmlUtf8);
begin
  BindValue(Slot, LandrixXmlXPathStringItem(Value));
end;

procedure TLandrixXmlXPathEvaluator.BindLazy(Slot: Integer; Expr: TLandrixXmlXPathExpression; ContextNode: Integer);
var
  P: PSlot;
begin
  P := SlotRef(Slot);
  ClearSlot(P^);
  P^.State := xssLazy;
  P^.Expression := Expr;
  P^.ContextNode := ContextNode;
  if Slot < FGlobalCount then
    DropCachedValues;
end;

procedure TLandrixXmlXPathEvaluator.EnterExpression(Expr: TLandrixXmlXPathExpression;
  out SavedExpr: TLandrixXmlXPathExpression; out SavedBase: Integer);
var
  Need, I: Integer;
begin
  SavedExpr := FExpr;
  SavedBase := FLocalBase;
  FExpr := Expr;
  FNodes := Expr.NodeArray;
  Inc(FNesting);
  FCache := FindCache(Expr);
  FLocalBase := FLocalTop;
  Need := Expr.SlotCount - Expr.FirstLocalSlot;
  if Need > 0 then
  begin
    if FLocalTop + Need > Length(FLocals) then
      SetLength(FLocals, 2 * (FLocalTop + Need) + 8);
    for I := FLocalTop to FLocalTop + Need - 1 do
      FLocals[I] := LandrixXmlXPathEmpty;
    Inc(FLocalTop, Need);
  end;
end;

procedure TLandrixXmlXPathEvaluator.LeaveExpression(SavedExpr: TLandrixXmlXPathExpression; SavedBase: Integer);
begin
  FLocalTop := FLocalBase;
  Dec(FNesting);
  FExpr := SavedExpr;
  FLocalBase := SavedBase;
  if FExpr <> nil then
    FNodes := FExpr.NodeArray
  else
    FNodes := nil;
  FCache := FindCache(FExpr);
end;

function TLandrixXmlXPathEvaluator.ReadVariable(Slot: Integer): TLandrixXmlXPathSequence;
var
  P: PSlot;
  SavedExpr: TLandrixXmlXPathExpression;
  SavedBase, Node, SavedCurrent: Integer;
  Value: TLandrixXmlXPathSequence;
  Empty: TLandrixXmlXPathSequence;
  SavedPattern, SavedFinal: Boolean;
begin
  if Slot >= FExpr.FirstLocalSlot then
  begin
    Result := FLocals[FLocalBase + Slot - FExpr.FirstLocalSlot];
    Exit;
  end;
  P := SlotRef(Slot);
  case P^.State of
    xssValue:
      Result := P^.Value;
    xssLazy:
      begin
        P^.State := xssEvaluating;
        Node := P^.ContextNode;
        Empty := LandrixXmlXPathEmpty;
        { current() is the variable's own context item (the document for
          a global, the rule's node for a rule variable, none for -1) }
        SavedCurrent := FCurrentNode;
        FCurrentNode := Node;
        { a variable read in a pattern still has its value as an expression }
        SavedPattern := FPattern;
        SavedFinal := FFinal;
        FPattern := False;
        EnterExpression(P^.Expression, SavedExpr, SavedBase);
        try
          try
            if Node >= 0 then
              Value := Eval(FExpr.Root, Node, 1, 1, Empty)
            else
              Value := Eval(FExpr.Root, -1, 0, 0, Empty);
          finally
            LeaveExpression(SavedExpr, SavedBase);
            FCurrentNode := SavedCurrent;
            FPattern := SavedPattern;
            FFinal := SavedFinal;
          end;
        except
          on E: ELandrixXmlXPathError do
          begin
            { the slot may have moved if the frame grew: look it up again }
            P := SlotRef(Slot);
            P^.State := xssError;
            P^.ErrorCode := E.XPathCode;
            P^.ErrorMessage := E.Message;
            raise;
          end;
          on Exception do
          begin
            { not an XPath error: evaluate again next time }
            P := SlotRef(Slot);
            P^.State := xssLazy;
            raise;
          end;
        end;
        P := SlotRef(Slot);
        if P^.DeclaredType.Declared then
        begin
          try
            Value := ConvertTo(Value, P^.DeclaredType, 'variable');
          except
            on E: ELandrixXmlXPathError do
            begin
              P := SlotRef(Slot);
              P^.State := xssError;
              P^.ErrorCode := E.XPathCode;
              P^.ErrorMessage := E.Message;
              raise;
            end;
          end;
          P := SlotRef(Slot);
        end;
        P^.State := xssValue;
        P^.Value := Value;
        Result := Value;
      end;
    xssEvaluating:
      begin
        Fail('XTDE0640', 'circular definition of variable slot ' + IntToStr(Slot));
        Result := LandrixXmlXPathEmpty;
      end;
    xssError:
      begin
        raise ELandrixXmlXPathError.CreateXPath(P^.ErrorCode, Copy(P^.ErrorMessage, Length(P^.ErrorCode) + 3, MaxInt));
      end;
  else
    Fail('XPDY0002', 'variable slot ' + IntToStr(Slot) + ' is not bound');
    Result := LandrixXmlXPathEmpty;
  end;
end;

procedure TLandrixXmlXPathEvaluator.WriteLocal(Slot: Integer; const Value: TLandrixXmlXPathSequence);
begin
  FLocals[FLocalBase + Slot - FExpr.FirstLocalSlot] := Value;
end;

function TLandrixXmlXPathEvaluator.StringOf(const Item: TLandrixXmlXPathItem): TLandrixXmlUtf8;
begin
  if Item.Kind = xikNode then
    Result := FTree.StringValueUtf8(Item.Node)
  else
    Result := AtomicString(Item);
end;

{ fn:data: nodes become their typed value (untypedAtomic, xs:string for
  comments and processing instructions). }
function TLandrixXmlXPathEvaluator.Atomize(const S: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
var
  I: Integer;
  HasNode: Boolean;
begin
  HasNode := False;
  for I := 0 to S.Count - 1 do
    if S.Items[I].Kind = xikNode then
    begin
      HasNode := True;
      Break;
    end;
  if not HasNode then
  begin
    Result := S;
    Exit;
  end;
  Result := LandrixXmlXPathEmpty;
  SetLength(Result.Items, S.Count);
  for I := 0 to S.Count - 1 do
    if S.Items[I].Kind = xikNode then
    begin
      if FTree.Kind[S.Items[I].Node] in [xnkComment, xnkProcessingInstruction] then
        LandrixXmlXPathAppend(Result, StringItem(xikString, FTree.StringValueUtf8(S.Items[I].Node)))
      else
        LandrixXmlXPathAppend(Result, StringItem(xikUntypedAtomic, FTree.StringValueUtf8(S.Items[I].Node)));
    end
    else
      LandrixXmlXPathAppend(Result, S.Items[I]);
end;

function TLandrixXmlXPathEvaluator.Regex(const Pattern, Flags: TLandrixXmlUtf8): TLandrixXmlRegex;
var
  Key: TLandrixXmlUtf8;
  I: Integer;
begin
  Key := Flags + #0 + Pattern;
  for I := Integer(FRegexes.Count) - 1 downto 0 do
    if FRegexKeys[I] = Key then
    begin
      Result := TLandrixXmlRegex(FRegexes[I]);
      Exit;
    end;
  try
    Result := TLandrixXmlRegex.Create(Pattern, xrmXPath, Flags);
  except
    on E: ELandrixXmlError do
    begin
      if E.Code = xecUnsupported then
        Fail('FOER0000', 'unsupported regular expression: ' + E.Message);
      Fail('FORX0002', 'invalid regular expression: ' + E.Message);
      Result := nil;
      Exit;
    end;
  end;
  if FRegexes.Count = Length(FRegexKeys) then
    SetLength(FRegexKeys, 2 * Integer(FRegexes.Count) + 8);
  FRegexKeys[FRegexes.Count] := Key;
  FRegexes.Add(Result);
end;

{ --- evaluation ---------------------------------------------------------------- }

function TLandrixXmlXPathEvaluator.EvaluateSequence(Expr: TLandrixXmlXPathExpression;
  ContextNode: Integer): TLandrixXmlXPathSequence;
var
  I: Integer;
begin
  Result := EvaluateShared(Expr, ContextNode);
  { the caller's own copy, with the digits of numbers and dates: the
    items may be kept values or a variable's }
  Result.Items := Copy(Result.Items, 0, Result.Count);
  for I := 0 to Result.Count - 1 do
  begin
    Result.Items[I].Decimal.Limbs := Copy(Result.Items[I].Decimal.Limbs, 0, Length(Result.Items[I].Decimal.Limbs));
    Result.Items[I].DateTime.Second.Limbs := Copy(Result.Items[I].DateTime.Second.Limbs, 0,
      Length(Result.Items[I].DateTime.Second.Limbs));
  end;
end;

function TLandrixXmlXPathEvaluator.EvaluatePattern(Expr: TLandrixXmlXPathExpression;
  ContextNode: Integer): TLandrixXmlXPathSequence;
begin
  FPattern := True;
  FFinal := True;
  FFailedCount := 0;
  FMinFailed := MaxInt;
  try
    Result := EvaluateSequence(Expr, ContextNode);
  finally
    FPattern := False;
    FFinal := False;
    FFailedCount := 0;
  end;
end;

procedure TLandrixXmlXPathEvaluator.AddFailed(Node: Integer);
begin
  if FFailedCount = Length(FFailed) then
    SetLength(FFailed, 2 * FFailedCount + 16);
  FFailed[FFailedCount] := Node;
  Inc(FFailedCount);
end;

{ S without the nodes FFailed[First .. Last - 1] }
function TLandrixXmlXPathEvaluator.WithoutFailed(const S: TLandrixXmlXPathSequence;
  First, Last: Integer): TLandrixXmlXPathSequence;
var
  Failed: array of Boolean;
  I: Integer;
begin
  Failed := nil;
  SetLength(Failed, FTree.Count);
  for I := First to Last - 1 do
    Failed[FFailed[I]] := True;
  Result := LandrixXmlXPathEmpty;
  for I := 0 to S.Count - 1 do
    if not Failed[S.Items[I].Node] then
      LandrixXmlXPathAppend(Result, S.Items[I]);
end;

function TLandrixXmlXPathEvaluator.EvaluateShared(Expr: TLandrixXmlXPathExpression;
  ContextNode: Integer): TLandrixXmlXPathSequence;
var
  SavedExpr: TLandrixXmlXPathExpression;
  SavedBase: Integer;
  Empty: TLandrixXmlXPathSequence;
begin
  Empty := LandrixXmlXPathEmpty;
  EnterExpression(Expr, SavedExpr, SavedBase);
  try
    try
      if ContextNode >= 0 then
        Result := Eval(Expr.Root, ContextNode, 1, 1, Empty)
      else
        Result := Eval(Expr.Root, -1, 0, 0, Empty);
    except
      { errors of the number and string units become XPath errors }
      on E: ELandrixXmlXPathError do
        raise;
      on E: ELandrixXmlError do
        case E.Code of
          xecArithmetic: Fail('FOAR0002', E.Message);
          xecConversion: Fail('FOCA0002', E.Message);
          xecRegex: Fail('FORX0002', E.Message);
        else
          Fail('FOER0000', E.Message);
        end;
    end;
  finally
    LeaveExpression(SavedExpr, SavedBase);
  end;
end;

function TLandrixXmlXPathEvaluator.Evaluate(Expr: TLandrixXmlXPathExpression;
  ContextNode: Integer): TLandrixXmlXPathResult;
begin
  Result := TLandrixXmlXPathResult.Create;
  try
    Result.FTree := FTree;
    Result.FItems := EvaluateSequence(Expr, ContextNode);
  except
    Result.Free;
    raise;
  end;
end;

function TLandrixXmlXPathEvaluator.EvaluateBoolean(Expr: TLandrixXmlXPathExpression; ContextNode: Integer): Boolean;
begin
  Result := SequenceBoolean(EvaluateShared(Expr, ContextNode));
end;

function TLandrixXmlXPathEvaluator.EvaluateString(Expr: TLandrixXmlXPathExpression;
  ContextNode: Integer): TLandrixXmlUtf8;
var
  S: TLandrixXmlXPathSequence;
  I: Integer;
begin
  S := EvaluateShared(Expr, ContextNode);
  Result := '';
  for I := 0 to S.Count - 1 do
  begin
    if I > 0 then
      Result := Result + ' ';
    Result := Result + StringOf(S.Items[I]);
  end;
end;

{ Node identity and document order: merges, sorts, removes duplicates. }
procedure SortNodes(var S: TLandrixXmlXPathSequence);
var
  I, J, N: Integer;
  T: TLandrixXmlXPathItem;
  Sorted: Boolean;
begin
  Sorted := True;
  for I := 1 to S.Count - 1 do
    if S.Items[I].Node <= S.Items[I - 1].Node then
    begin
      Sorted := False;
      Break;
    end;
  if Sorted then
    Exit;
  { shell sort on the node index }
  N := 1;
  while N < S.Count div 3 do
    N := 3 * N + 1;
  while N >= 1 do
  begin
    for I := N to S.Count - 1 do
    begin
      T := S.Items[I];
      J := I;
      while (J >= N) and (S.Items[J - N].Node > T.Node) do
      begin
        S.Items[J] := S.Items[J - N];
        Dec(J, N);
      end;
      S.Items[J] := T;
    end;
    N := N div 3;
  end;
  J := 0;
  for I := 0 to S.Count - 1 do
    if (J = 0) or (S.Items[I].Node <> S.Items[J - 1].Node) then
    begin
      S.Items[J] := S.Items[I];
      Inc(J);
    end;
  S.Count := J;
end;

{ An error in a pattern's predicate that means "no match": a dynamic
  error of the rules. Not what this implementation does not support
  (FOER0000, XPST0017, xecUnsupported and the like) and not a circular
  variable (XTDE0640): these are raised. }
function PatternMismatch(E: ELandrixXmlError): Boolean;
var
  Code: string;
begin
  if E is ELandrixXmlXPathError then
  begin
    Code := ELandrixXmlXPathError(E).XPathCode;
    Result := (Code <> 'XTDE0640') and (Code <> 'FOER0000') and (Code <> 'XPST0017');
  end
  else
    Result := E.Code in [xecArithmetic, xecConversion, xecRegex];
end;

{ True if the value of Index may be a number (a predicate then compares
  it with the position); only for the predicates of a pattern. }
function MayBeNumeric(const Nodes: TLandrixXmlXPathAstNodes; Index: Integer): Boolean;
const
  Numeric = [xfnCount, xfnSum, xfnAvg, xfnMin, xfnMax, xfnStringLength, xfnNumber, xfnAbs, xfnRound,
    xfnRoundHalfToEven, xfnFloor, xfnCeiling, xfnPosition, xfnLast, xfnIndexOf, xfnStringToCodepoints,
    xfnXsDecimal, xfnXsInteger, xfnXsDouble, xfnXsFloat];
  { the items of the first argument (distinct-values and data atomize
    them: untyped values, numbers only if the argument has numbers) }
  PassOn = [xfnReverse, xfnDistinctValues, xfnSubsequence, xfnData, xfnExactlyOne, xfnZeroOrOne,
    xfnOneOrMore];
var
  J: Integer;
begin
  case Nodes[Index].Kind of
    { "." too: a pattern's predicates are evaluated on nodes }
    xakGeneralCompare, xakValueCompare, xakAnd, xakOr, xakString, xakCastable, xakUnion, xakSome, xakEvery,
    xakStep, xakEmpty, xakRoot, xakContextItem:
      Result := False;
    xakPath:
      Result := Nodes[Nodes[Index].Children[Integer(High(Nodes[Index].Children))]].Kind <> xakStep;
    xakIf:
      Result := MayBeNumeric(Nodes, Nodes[Index].Children[1]) or MayBeNumeric(Nodes, Nodes[Index].Children[2]);
    xakLet:
      Result := MayBeNumeric(Nodes, Nodes[Index].Children[1]);
    { a filter keeps items of its input }
    xakFilter:
      Result := MayBeNumeric(Nodes, Nodes[Index].Children[0]);
    xakSequence:
      begin
        Result := False;
        for J := 0 to Integer(High(Nodes[Index].Children)) do
          if MayBeNumeric(Nodes, Nodes[Index].Children[J]) then
            Result := True;
      end;
    xakCast:
      Result := Nodes[Index].AtomicType in [xatAnyAtomic, xatDecimal, xatInteger, xatDouble, xatFloat];
    xakFunction:
      if Nodes[Index].Op < 0 then
        Result := True
      else if TLandrixXmlXPathFunctionId(Nodes[Index].Op) in PassOn then
        Result := (Length(Nodes[Index].Children) = 0) or MayBeNumeric(Nodes, Nodes[Index].Children[0])
      else
        Result := TLandrixXmlXPathFunctionId(Nodes[Index].Op) in Numeric;
  else
    { numbers, arithmetic, ranges, for, variables and user functions (of
      unknown type): possibly numeric, as Saxon treats them }
    Result := True;
  end;
end;

{ True if Index calls position() or last() of its own focus: not inside
  a predicate or a later step of a path, where the focus is another. }
function UsesOwnPosition(const Nodes: TLandrixXmlXPathAstNodes; Index: Integer): Boolean;
var
  J: Integer;
begin
  Result := (Nodes[Index].Kind = xakFunction) and (Nodes[Index].Op >= 0) and
    (TLandrixXmlXPathFunctionId(Nodes[Index].Op) in [xfnPosition, xfnLast]);
  if Result then
    Exit;
  if Nodes[Index].Kind = xakPath then
  begin
    if not Nodes[Index].RootStart then
      Result := UsesOwnPosition(Nodes, Nodes[Index].Children[0]);
    Exit;
  end;
  J := 0;
  while not Result and (J < Length(Nodes[Index].Children)) do
  begin
    Result := UsesOwnPosition(Nodes, Nodes[Index].Children[J]);
    Inc(J);
  end;
end;

{ a predicate's value: a number is a position }
function PredicateTrue(const V: TLandrixXmlXPathSequence; Pos: Integer): Boolean;
begin
  if (V.Count = 1) and IsNumeric(V.Items[0].Kind) then
    Result := NumericEqualsInteger(V.Items[0], Pos)
  else
    Result := SequenceBoolean(V);
end;

{ The position a predicate asks for as an integer literal ([2]); 0 if
  it is none. }
function LiteralPosition(const Nodes: TLandrixXmlXPathAstNodes; Index: Integer): Int64;
begin
  { xs:integer(1) too }
  if (Nodes[Index].Kind = xakFunction) and (Nodes[Index].Op >= 0) and
    (TLandrixXmlXPathFunctionId(Nodes[Index].Op) = xfnXsInteger) and (Length(Nodes[Index].Children) = 1) then
    Index := Nodes[Index].Children[0];
  if (Nodes[Index].Kind <> xakInteger) or not LandrixXmlDecimalTryToInt64(Nodes[Index].Decimal, Result) then
    Result := 0;
end;

{ Removes the items of a pattern from the node FailAt on (patterns use
  forward axes, so node order is axis order), or all of them; on the
  last step of a branch they count as failed. }
procedure TLandrixXmlXPathEvaluator.CutAfterFailure(var S: TLandrixXmlXPathSequence; FailAt: Integer;
  All, Final: Boolean);
var
  I, J: Integer;
begin
  J := 0;
  for I := 0 to S.Count - 1 do
    if not All and (S.Items[I].Node < FailAt) then
    begin
      S.Items[J] := S.Items[I];
      Inc(J);
    end
    else if Final then
      AddFailed(S.Items[I].Node);
  S.Count := J;
end;

{ In a pattern, a predicate failing on an item makes the positions of
  the items after it unknown (FailAt, the first such node; InputFailedAt
  for the input of a filter, MaxInt if none). A later predicate that may
  use the position then sees, as Saxon, which counts a candidate's
  position over the items before it: [k] the k-th item if it comes
  before FailAt (the positions are known again after it) and no item
  otherwise; a predicate calling position() or last() no item; another
  number only the items before FailAt. }
function TLandrixXmlXPathEvaluator.ApplyPredicates(const Predicates: array of Integer;
  const Input: TLandrixXmlXPathSequence; InputFailedAt: Integer): TLandrixXmlXPathSequence;
var
  P, I, Pos, Size, FailAt, Before: Integer;
  K: Int64;
  Current, Next: TLandrixXmlXPathSequence;
  Keep, Pattern, Final, Own: Boolean;
  Ctx: TLandrixXmlXPathSequence;
begin
  Current := Input;
  { a pattern's own predicates: what they contain is evaluated as usual }
  Pattern := FPattern;
  Final := FFinal;
  FPattern := False;
  FailAt := InputFailedAt;
  try
    for P := 0 to Integer(High(Predicates)) do
    begin
      Own := Pattern and (FailAt < MaxInt) and UsesOwnPosition(FNodes, Predicates[P]);
      if Pattern and (FailAt < MaxInt) and (Own or MayBeNumeric(FNodes, Predicates[P])) then
      begin
        { a new sequence: Current may be Input, the storage of a variable }
        Next := LandrixXmlXPathEmpty;
        AppendAll(Next, Current);
        Current := Next;
        K := LiteralPosition(FNodes, Predicates[P]);
        Before := 0;
        for I := 0 to Current.Count - 1 do
          if Current.Items[I].Node < FailAt then
            Inc(Before);
        if Own or (K > Before) then
          CutAfterFailure(Current, FailAt, True, Final)
        else if K > 0 then
          FailAt := MaxInt
        else
          CutAfterFailure(Current, FailAt, False, Final);
      end;
      Next := LandrixXmlXPathEmpty;
      Size := Current.Count;
      for I := 0 to Size - 1 do
      begin
        { the input is in axis order (nearest first on reverse axes) }
        Pos := I + 1;
        Ctx := SingleSeq(Current.Items[I]);
        if not Pattern then
          Keep := PredicateTrue(Eval(Predicates[P], Current.Items[I].Node, Pos, Size, Ctx), Pos)
        else
        begin
          { an error: the item does not match the pattern }
          Keep := False;
          try
            if PredicateTrue(Eval(Predicates[P], Current.Items[I].Node, Pos, Size, Ctx), Pos) then
              Keep := True;
          except
            on E: ELandrixXmlError do
              if PatternMismatch(E) then
              begin
                if Current.Items[I].Node < FailAt then
                  FailAt := Current.Items[I].Node;
                if Final then
                  AddFailed(Current.Items[I].Node);
              end
              else
                raise;
          end;
        end;
        if Keep then
          LandrixXmlXPathAppend(Next, Current.Items[I]);
      end;
      Current := Next;
    end;
    { what is still unknown after the last predicate, for a filter around }
    if Pattern and (FailAt < FMinFailed) then
      FMinFailed := FailAt;
  finally
    FPattern := Pattern;
    FFinal := Final;
  end;
  Result := Current;
end;

{ The step Index from Node; Axis is the step's own axis, or descendant
  for a child step that follows "//" (see TExpressionCache.Fuse). }
function TLandrixXmlXPathEvaluator.EvalStep(Index: Integer; Node: Integer;
  Axis: TLandrixXmlXPathAxis): TLandrixXmlXPathSequence;
var
  N: ^TLandrixXmlXPathAstNode;
  Expanded, I, E: Integer;
  Out1: TLandrixXmlXPathSequence;
  Reverse: Boolean;
  Item: TLandrixXmlXPathItem;
  AttributeAxis: Boolean;

  function Test(I: Integer): Boolean;
  var
    K: TLandrixXmlXPathNodeKind;
  begin
    K := FTree.Kind[I];
    case N^.NodeTest of
      xntAnyNode: Result := True;
      xntText: Result := K = xnkText;
      xntComment: Result := K = xnkComment;
      xntProcessingInstruction:
        Result := (K = xnkProcessingInstruction) and ((N^.LocalName = '') or (FTree.LocalNameUtf8(I) = N^.LocalName));
      xntDocumentNode: Result := K = xnkDocument;
      xntAnyElement: Result := K = xnkElement;
      xntAnyAttribute: Result := K = xnkAttribute;
    else
      { name tests: the principal node kind of the axis }
      if AttributeAxis then
        Result := K = xnkAttribute
      else
        Result := K = xnkElement;
      if Result then
        case N^.NodeTest of
          xntName: Result := (Expanded >= 0) and (FTree.ExpandedName[I] = Expanded);
          xntNamespaceWildcard: Result := FTree.NamespaceUriUtf8(I) = N^.NamespaceUri;
          xntLocalWildcard: Result := FTree.LocalNameUtf8(I) = N^.LocalName;
        else
          { * }
        end;
    end;
  end;

  procedure Add(I: Integer);
  begin
    if Test(I) then
    begin
      Item.Node := I;
      LandrixXmlXPathAppend(Out1, Item);
    end;
  end;

  procedure AddDescendants(From: Integer);
  var
    J: Integer;
  begin
    for J := From + 1 to FTree.SubtreeEnd[From] do
      if FTree.Kind[J] <> xnkAttribute then
        Add(J);
  end;

begin
  N := @FNodes[Index];
  Out1 := LandrixXmlXPathEmpty;
  InitItem(Item, xikNode);
  Reverse := False;
  AttributeAxis := Axis = xaxAttribute;
  Expanded := -1;
  if N^.NodeTest = xntName then
    Expanded := FTree.FindExpandedName(N^.NamespaceUri, N^.LocalName);
  case Axis of
    xaxChild:
      begin
        I := FTree.FirstChild(Node);
        while I >= 0 do
        begin
          Add(I);
          I := FTree.NextSibling[I];
        end;
      end;
    xaxDescendant:
      if FTree.Kind[Node] <> xnkAttribute then
        AddDescendants(Node);
    xaxDescendantOrSelf:
      begin
        Add(Node);
        if FTree.Kind[Node] <> xnkAttribute then
          AddDescendants(Node);
      end;
    xaxAttribute:
      if FTree.Kind[Node] = xnkElement then
        for I := Node + 1 to Node + FTree.AttributeCount[Node] do
          Add(I);
    xaxSelf:
      Add(Node);
    xaxParent:
      if FTree.Parent[Node] >= 0 then
        Add(FTree.Parent[Node]);
    xaxAncestor, xaxAncestorOrSelf:
      begin
        Reverse := True;
        if Axis = xaxAncestorOrSelf then
          Add(Node);
        I := FTree.Parent[Node];
        while I >= 0 do
        begin
          Add(I);
          I := FTree.Parent[I];
        end;
      end;
    xaxFollowingSibling:
      if FTree.Kind[Node] <> xnkAttribute then
      begin
        I := FTree.NextSibling[Node];
        while I >= 0 do
        begin
          Add(I);
          I := FTree.NextSibling[I];
        end;
      end;
    xaxPrecedingSibling:
      if (FTree.Kind[Node] <> xnkAttribute) and (FTree.Parent[Node] >= 0) then
      begin
        Reverse := True;
        { nearest first }
        I := FTree.FirstChild(FTree.Parent[Node]);
        E := Out1.Count;
        while (I >= 0) and (I <> Node) do
        begin
          Add(I);
          I := FTree.NextSibling[I];
        end;
        { reverse what was added }
        for I := 0 to (Out1.Count - E) div 2 - 1 do
        begin
          Item := Out1.Items[E + I];
          Out1.Items[E + I] := Out1.Items[Out1.Count - 1 - I];
          Out1.Items[Out1.Count - 1 - I] := Item;
        end;
      end;
    xaxPreceding:
      begin
        Reverse := True;
        { nodes before Node in document order, without its ancestors and without attributes }
        I := Node;
        if FTree.Kind[I] = xnkAttribute then
          I := FTree.Parent[I];
        E := I - 1;
        while E > 0 do
        begin
          if (FTree.Kind[E] <> xnkAttribute) and (FTree.SubtreeEnd[E] < I) then
            Add(E);
          Dec(E);
        end;
      end;
  end;
  if Length(N^.Predicates) > 0 then
    Out1 := ApplyPredicates(N^.Predicates, Out1, MaxInt);
  if Reverse then
    SortNodes(Out1);
  Result := Out1;
end;

function TLandrixXmlXPathEvaluator.EvalPath(Index: Integer; Context, Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
var
  N: ^TLandrixXmlXPathAstNode;
  K, I, Step, First: Integer;
  Current, Next, Part, Ctx: TLandrixXmlXPathSequence;
  AllNodes, AllAtomic, Final: Boolean;
  Axis: TLandrixXmlXPathAxis;
begin
  N := @FNodes[Index];
  { in a pattern, only the last step's items are candidates; not restored
    on an exception, which ends EvaluatePattern (code that catches one
    runs with FPattern off and does not use FFinal) }
  Final := FFinal;
  if FPattern then
    FFinal := False;
  if N^.RootStart then
  begin
    if Context < 0 then
      Fail('XPDY0002', 'the context item for "/" is absent or not a node');
    Current := LandrixXmlXPathNodeItem(0);
    First := 0;
  end
  else
  begin
    Current := Eval(N^.Children[0], Context, Position, Size, ContextItem);
    First := 1;
  end;
  K := First;
  while K <= Integer(High(N^.Children)) do
  begin
    Step := N^.Children[K];
    N := @FNodes[Index];
    Axis := FNodes[Step].Axis;
    { "//" and a child step: the descendants, as one step }
    if (FCache <> nil) and (FNodes[Step].Kind = xakStep) and (Axis = xaxDescendantOrSelf) and
      (FNodes[Step].NodeTest = xntAnyNode) and (Length(FNodes[Step].Predicates) = 0) and
      (K < Integer(High(N^.Children))) and TExpressionCache(FCache).Fuse[N^.Children[K + 1]] then
    begin
      Inc(K);
      Step := N^.Children[K];
      Axis := xaxDescendant;
    end;
    if FPattern then
      FFinal := Final and (K = Integer(High(N^.Children)));
    Next := LandrixXmlXPathEmpty;
    AllNodes := True;
    AllAtomic := True;
    for I := 0 to Current.Count - 1 do
    begin
      if Current.Items[I].Kind <> xikNode then
        Fail('XPTY0019', 'the left side of "/" contains an atomic value');
      if FNodes[Step].Kind = xakStep then
        Part := EvalStep(Step, Current.Items[I].Node, Axis)
      else
      begin
        Ctx := SingleSeq(Current.Items[I]);
        Part := Eval(Step, Current.Items[I].Node, I + 1, Current.Count, Ctx);
      end;
      AppendAll(Next, Part);
    end;
    for I := 0 to Next.Count - 1 do
      if Next.Items[I].Kind = xikNode then
        AllAtomic := False
      else
        AllNodes := False;
    if AllNodes then
      SortNodes(Next)
    else if not AllAtomic then
      Fail('XPTY0018', 'the result of a path contains nodes and atomic values');
    Current := Next;
    Inc(K);
  end;
  if FPattern then
    FFinal := Final;
  Result := Current;
end;

{ for, some, every over bindings Binding .. Count - 2 (the last child is
  the return or satisfies expression). Returns True to stop (some found a
  true item, every a false one). }
function TLandrixXmlXPathEvaluator.EvalQuantified(Index, Binding: Integer; Context, Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence; Kind: TLandrixXmlXPathAstKind;
  var Output: TLandrixXmlXPathSequence): Boolean;
var
  Values, V: TLandrixXmlXPathSequence;
  I, Last, Slot: Integer;
  Body: Integer;
begin
  Result := False;
  Last := Integer(High(FNodes[Index].Children));
  if Binding = Last then
  begin
    Body := FNodes[Index].Children[Last];
    V := Eval(Body, Context, Position, Size, ContextItem);
    case Kind of
      xakFor:
        AppendAll(Output, V);
      xakSome:
        Result := SequenceBoolean(V);
      xakEvery:
        Result := not SequenceBoolean(V);
    else
      { not a quantifier }
    end;
    Exit;
  end;
  Values := Eval(FNodes[Index].Children[Binding], Context, Position, Size, ContextItem);
  Slot := FNodes[Index].Slots[Binding];
  for I := 0 to Values.Count - 1 do
  begin
    WriteLocal(Slot, SingleSeq(Values.Items[I]));
    if EvalQuantified(Index, Binding + 1, Context, Position, Size, ContextItem, Kind, Output) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function TLandrixXmlXPathEvaluator.Eval(Index: Integer; Context: Integer; Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
var
  N: ^TLandrixXmlXPathAstNode;
  A, B: TLandrixXmlXPathSequence;
  I: Integer;
  Left, Right: Boolean;
  LeftError: ELandrixXmlXPathError;
  ErrCode, ErrMsg: string;
  Mark, Split: Integer;
begin
  { a pattern's steps (not their predicates) are not kept: their value is
    not that of the expression }
  if (FCache <> nil) and (Context >= 0) and (Index <> FBypass) and not FPattern and
    TExpressionCache(FCache).Flags[Index] then
  begin
    Result := CachedEval(Index, Context, Position, Size, ContextItem);
    Exit;
  end;
  FBypass := -1;
  N := @FNodes[Index];
  case N^.Kind of
    xakSequence:
      begin
        Result := LandrixXmlXPathEmpty;
        for I := 0 to Integer(High(N^.Children)) do
        begin
          A := Eval(FNodes[Index].Children[I], Context, Position, Size, ContextItem);
          AppendAll(Result, A);
        end;
      end;
    xakEmpty:
      Result := LandrixXmlXPathEmpty;
    xakString:
      Result := LandrixXmlXPathStringItem(N^.Text);
    xakInteger:
      Result := SingleSeq(IntegerItem(N^.Decimal));
    xakDecimal:
      Result := SingleSeq(DecimalItem(N^.Decimal));
    xakDouble:
      Result := SingleSeq(DoubleItem(N^.DoubleValue));
    xakVariable:
      Result := ReadVariable(N^.Slot);
    xakContextItem:
      begin
        if ContextItem.Count > 0 then
          Result := ContextItem
        else if Context >= 0 then
          Result := LandrixXmlXPathNodeItem(Context)
        else
        begin
          Fail('XPDY0002', 'the context item is absent');
          Result := LandrixXmlXPathEmpty;
        end;
      end;
    xakRoot:
      begin
        if Context < 0 then
          Fail('XPDY0002', 'the context item for "/" is absent or not a node');
        Result := LandrixXmlXPathNodeItem(0);
      end;
    xakStep:
      begin
        if Context < 0 then
          Fail('XPTY0020', 'the context item for an axis step is not a node');
        Result := EvalStep(Index, Context, N^.Axis);
      end;
    xakPath:
      Result := EvalPath(Index, Context, Position, Size, ContextItem);
    xakFilter:
      begin
        { what the input leaves unknown goes to the predicates, which
          resolve it or pass it on }
        Mark := FMinFailed;
        FMinFailed := MaxInt;
        try
          A := Eval(N^.Children[0], Context, Position, Size, ContextItem);
        finally
          Split := FMinFailed;
          FMinFailed := Mark;
        end;
        Result := ApplyPredicates(FNodes[Index].Predicates, A, Split);
      end;
    xakFor, xakSome, xakEvery:
      begin
        Result := LandrixXmlXPathEmpty;
        Left := EvalQuantified(Index, 0, Context, Position, Size, ContextItem, N^.Kind, Result);
        case FNodes[Index].Kind of
          xakSome:
            Result := BooleanSeq(Left);
          xakEvery:
            Result := BooleanSeq(not Left);
        else
          { for: the collected items }
        end;
      end;
    xakIf:
      begin
        A := Eval(N^.Children[0], Context, Position, Size, ContextItem);
        if SequenceBoolean(A) then
          Result := Eval(FNodes[Index].Children[1], Context, Position, Size, ContextItem)
        else
          Result := Eval(FNodes[Index].Children[2], Context, Position, Size, ContextItem);
      end;
    xakAnd, xakOr:
      begin
        { like Saxon: an error in one operand does not matter if the other
          one decides }
        LeftError := nil;
        Left := False;
        ErrCode := '';
        ErrMsg := '';
        try
          Left := SequenceBoolean(Eval(N^.Children[0], Context, Position, Size, ContextItem));
        except
          on E: ELandrixXmlXPathError do
          begin
            LeftError := E;
            ErrCode := E.XPathCode;
            ErrMsg := Copy(E.Message, Length(E.XPathCode) + 3, MaxInt);
          end;
        end;
        if (LeftError = nil) and (Left = (FNodes[Index].Kind = xakOr)) then
        begin
          Result := BooleanSeq(Left);
          Exit;
        end;
        Right := SequenceBoolean(Eval(FNodes[Index].Children[1], Context, Position, Size, ContextItem));
        if LeftError <> nil then
        begin
          if Right = (FNodes[Index].Kind = xakOr) then
          begin
            Result := BooleanSeq(Right);
            Exit;
          end;
          raise ELandrixXmlXPathError.CreateXPath(ErrCode, ErrMsg);
        end;
        Result := BooleanSeq(Right);
      end;
    xakGeneralCompare:
      begin
        A := Atomize(Eval(N^.Children[0], Context, Position, Size, ContextItem));
        B := Atomize(Eval(FNodes[Index].Children[1], Context, Position, Size, ContextItem));
        Result := BooleanSeq(GeneralCompare(A, B, TLandrixXmlXPathCompare(FNodes[Index].Op)));
      end;
    xakValueCompare:
      begin
        A := Atomize(Eval(N^.Children[0], Context, Position, Size, ContextItem));
        B := Atomize(Eval(FNodes[Index].Children[1], Context, Position, Size, ContextItem));
        if (A.Count = 0) or (B.Count = 0) then
          Result := LandrixXmlXPathEmpty
        else
        begin
          if (A.Count > 1) or (B.Count > 1) then
            Fail('XPTY0004', 'a value comparison needs single items');
          Result := BooleanSeq(ValueCompare(A.Items[0], B.Items[0], TLandrixXmlXPathCompare(FNodes[Index].Op)));
        end;
      end;
    xakRange:
      begin
        A := Atomize(Eval(N^.Children[0], Context, Position, Size, ContextItem));
        B := Atomize(Eval(FNodes[Index].Children[1], Context, Position, Size, ContextItem));
        Result := RangeOf(A, B);
      end;
    xakArithmetic:
      begin
        A := Atomize(Eval(N^.Children[0], Context, Position, Size, ContextItem));
        B := Atomize(Eval(FNodes[Index].Children[1], Context, Position, Size, ContextItem));
        if (A.Count = 0) or (B.Count = 0) then
          Result := LandrixXmlXPathEmpty
        else
        begin
          if (A.Count > 1) or (B.Count > 1) then
            Fail('XPTY0004', 'arithmetic needs single items');
          Result := SingleSeq(Arithmetic(A.Items[0], B.Items[0], TLandrixXmlXPathArithmetic(FNodes[Index].Op)));
        end;
      end;
    xakNegate, xakUnaryPlus:
      begin
        A := Atomize(Eval(N^.Children[0], Context, Position, Size, ContextItem));
        if A.Count = 0 then
          Result := LandrixXmlXPathEmpty
        else
        begin
          if A.Count > 1 then
            Fail('XPTY0004', 'a unary minus needs a single item');
          Result := SingleSeq(UnaryOp(A.Items[0], FNodes[Index].Kind = xakNegate));
        end;
      end;
    xakUnion:
      begin
        Mark := FFailedCount;
        A := Eval(N^.Children[0], Context, Position, Size, ContextItem);
        Split := FFailedCount;
        B := Eval(FNodes[Index].Children[1], Context, Position, Size, ContextItem);
        for I := 0 to A.Count - 1 do
          if A.Items[I].Kind <> xikNode then
            Fail('XPTY0004', 'the operands of "|" must be nodes');
        for I := 0 to B.Count - 1 do
          if B.Items[I].Kind <> xikNode then
            Fail('XPTY0004', 'the operands of "|" must be nodes');
        { a pattern: a node the left side failed on does not match, as
          Saxon tries the branches in order }
        if FPattern and (Split > Mark) then
          B := WithoutFailed(B, Mark, Split);
        { a new sequence: A may be the storage of a variable }
        Result := LandrixXmlXPathEmpty;
        AppendAll(Result, A);
        AppendAll(Result, B);
        SortNodes(Result);
      end;
    xakCast, xakCastable:
      begin
        A := Atomize(Eval(N^.Children[0], Context, Position, Size, ContextItem));
        N := @FNodes[Index];
        if N^.Kind = xakCastable then
        begin
          if A.Count = 0 then
            Result := BooleanSeq(N^.AllowEmpty)
          else if A.Count > 1 then
            Result := BooleanSeq(False)
          else
            Result := BooleanSeq(Castable(A.Items[0], N^.AtomicType));
        end
        else if A.Count = 0 then
        begin
          if not N^.AllowEmpty then
            Fail('XPTY0004', 'an empty sequence cannot be cast to ' + LandrixXmlXPathAtomicTypeName(N^.AtomicType));
          Result := LandrixXmlXPathEmpty;
        end
        else
        begin
          if A.Count > 1 then
            Fail('XPTY0004', 'a sequence of several items cannot be cast');
          Result := SingleSeq(CastTo(A.Items[0], N^.AtomicType));
        end;
      end;
    xakFunction:
      Result := CallFunction(Index, Context, Position, Size, ContextItem);
  else
    Fail('FOER0000', 'expression kind not supported');
    Result := LandrixXmlXPathEmpty;
  end;
end;

{ Function conversion rules: the argument (or result) converted to the
  declared type: atomized, untypedAtomic cast to the atomic type,
  cardinality checked. }
function TLandrixXmlXPathEvaluator.CallUser(Def: TLandrixXmlXPathFunctionDef;
  const Args: array of TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
var
  SavedFrame: TLandrixXmlXPathSlots;
  SavedCurrent, I: Integer;
  SavedPattern: Boolean;
  SavedExpr: TLandrixXmlXPathExpression;
  SavedBase: Integer;
  Empty: TLandrixXmlXPathSequence;
begin
  if FDepth >= FMaxDepth then
    Fail('FOER0000', 'user functions nested deeper than ' + IntToStr(FMaxDepth));
  Inc(FDepth);
  SavedFrame := FFrame;
  SavedCurrent := FCurrentNode;
  SavedPattern := FPattern;
  { no current() inside a function, as in XSLT; its body is no pattern }
  FCurrentNode := -1;
  FPattern := False;
  FFrame := nil;
  try
    SetLength(FFrame, Def.FrameSize);
    for I := 0 to Def.FrameSize - 1 do
      ClearSlot(FFrame[I]);
    for I := 0 to Integer(High(Args)) do
    begin
      FFrame[Def.ParamSlots[I]].State := xssValue;
      FFrame[Def.ParamSlots[I]].Value := ConvertTo(Args[I], Def.ParamTypes[I], Def.Name);
    end;
    for I := 0 to Integer(Length(Def.LocalSlots)) - 1 do
    begin
      FFrame[Def.LocalSlots[I]].State := xssLazy;
      FFrame[Def.LocalSlots[I]].Expression := Def.LocalExpressions[I];
      FFrame[Def.LocalSlots[I]].ContextNode := -1;
      if I < Length(Def.LocalTypes) then
        FFrame[Def.LocalSlots[I]].DeclaredType := Def.LocalTypes[I];
    end;
    Empty := LandrixXmlXPathEmpty;
    EnterExpression(Def.Body, SavedExpr, SavedBase);
    try
      Result := Eval(Def.Body.Root, -1, 0, 0, Empty);
    finally
      LeaveExpression(SavedExpr, SavedBase);
    end;
    Result := ConvertTo(Result, Def.ResultType, Def.Name);
  finally
    FFrame := SavedFrame;
    FCurrentNode := SavedCurrent;
    FPattern := SavedPattern;
    Dec(FDepth);
  end;
end;

{$I LandrixXmlXPathFunctions.inc}

end.
