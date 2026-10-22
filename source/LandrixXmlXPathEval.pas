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
  (Saxon goes through xs:double there). }

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
    procedure EnterExpression(Expr: TLandrixXmlXPathExpression; out SavedExpr: TLandrixXmlXPathExpression;
      out SavedBase: Integer);
    procedure LeaveExpression(SavedExpr: TLandrixXmlXPathExpression; SavedBase: Integer);
    function SlotRef(Slot: Integer): Pointer;
    function ReadVariable(Slot: Integer): TLandrixXmlXPathSequence;
    procedure WriteLocal(Slot: Integer; const Value: TLandrixXmlXPathSequence);
    function Eval(Index: Integer; Context: Integer; Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    function EvalStep(Index: Integer; Node: Integer): TLandrixXmlXPathSequence;
    function EvalPath(Index: Integer; Context, Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    function ApplyPredicates(const Predicates: array of Integer;
      const Input: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
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
end;

destructor TLandrixXmlXPathEvaluator.Destroy;
begin
  FRegexes.Free;
  inherited Destroy;
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
  FGlobalCount := Count;
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
  FExpr := SavedExpr;
  FLocalBase := SavedBase;
  if FExpr <> nil then
    FNodes := FExpr.NodeArray
  else
    FNodes := nil;
end;

function TLandrixXmlXPathEvaluator.ReadVariable(Slot: Integer): TLandrixXmlXPathSequence;
var
  P: PSlot;
  SavedExpr: TLandrixXmlXPathExpression;
  SavedBase, Node, SavedCurrent: Integer;
  Value: TLandrixXmlXPathSequence;
  Empty: TLandrixXmlXPathSequence;
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
  Result := SequenceBoolean(EvaluateSequence(Expr, ContextNode));
end;

function TLandrixXmlXPathEvaluator.EvaluateString(Expr: TLandrixXmlXPathExpression;
  ContextNode: Integer): TLandrixXmlUtf8;
var
  S: TLandrixXmlXPathSequence;
  I: Integer;
begin
  S := EvaluateSequence(Expr, ContextNode);
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

function TLandrixXmlXPathEvaluator.ApplyPredicates(const Predicates: array of Integer;
  const Input: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
var
  P, I, Pos, Size: Integer;
  Current, Next, V: TLandrixXmlXPathSequence;
  Keep: Boolean;
  Ctx: TLandrixXmlXPathSequence;
begin
  Current := Input;
  for P := 0 to Integer(High(Predicates)) do
  begin
    Next := LandrixXmlXPathEmpty;
    Size := Current.Count;
    for I := 0 to Size - 1 do
    begin
      { the input is in axis order (nearest first on reverse axes) }
      Pos := I + 1;
      Ctx := SingleSeq(Current.Items[I]);
      V := Eval(Predicates[P], Current.Items[I].Node, Pos, Size, Ctx);
      if (V.Count = 1) and IsNumeric(V.Items[0].Kind) then
        Keep := NumericEqualsInteger(V.Items[0], Pos)
      else
        Keep := SequenceBoolean(V);
      if Keep then
        LandrixXmlXPathAppend(Next, Current.Items[I]);
    end;
    Current := Next;
  end;
  Result := Current;
end;

function TLandrixXmlXPathEvaluator.EvalStep(Index: Integer; Node: Integer): TLandrixXmlXPathSequence;
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
  AttributeAxis := N^.Axis = xaxAttribute;
  Expanded := -1;
  if N^.NodeTest = xntName then
    Expanded := FTree.FindExpandedName(N^.NamespaceUri, N^.LocalName);
  case N^.Axis of
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
        if N^.Axis = xaxAncestorOrSelf then
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
    Out1 := ApplyPredicates(N^.Predicates, Out1);
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
  AllNodes, AllAtomic: Boolean;
begin
  N := @FNodes[Index];
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
  for K := First to Integer(High(N^.Children)) do
  begin
    Step := N^.Children[K];
    N := @FNodes[Index];
    Next := LandrixXmlXPathEmpty;
    AllNodes := True;
    AllAtomic := True;
    for I := 0 to Current.Count - 1 do
    begin
      if Current.Items[I].Kind <> xikNode then
        Fail('XPTY0019', 'the left side of "/" contains an atomic value');
      if FNodes[Step].Kind = xakStep then
        Part := EvalStep(Step, Current.Items[I].Node)
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
  end;
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
begin
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
        Result := EvalStep(Index, Context);
      end;
    xakPath:
      Result := EvalPath(Index, Context, Position, Size, ContextItem);
    xakFilter:
      begin
        A := Eval(N^.Children[0], Context, Position, Size, ContextItem);
        Result := ApplyPredicates(FNodes[Index].Predicates, A);
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
        A := Eval(N^.Children[0], Context, Position, Size, ContextItem);
        B := Eval(FNodes[Index].Children[1], Context, Position, Size, ContextItem);
        for I := 0 to A.Count - 1 do
          if A.Items[I].Kind <> xikNode then
            Fail('XPTY0004', 'the operands of "|" must be nodes');
        for I := 0 to B.Count - 1 do
          if B.Items[I].Kind <> xikNode then
            Fail('XPTY0004', 'the operands of "|" must be nodes');
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
  SavedExpr: TLandrixXmlXPathExpression;
  SavedBase: Integer;
  Empty: TLandrixXmlXPathSequence;
begin
  if FDepth >= FMaxDepth then
    Fail('FOER0000', 'user functions nested deeper than ' + IntToStr(FMaxDepth));
  Inc(FDepth);
  SavedFrame := FFrame;
  SavedCurrent := FCurrentNode;
  { no current() inside a function, as in XSLT }
  FCurrentNode := -1;
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
    Dec(FDepth);
  end;
end;

{$I LandrixXmlXPathFunctions.inc}

end.
