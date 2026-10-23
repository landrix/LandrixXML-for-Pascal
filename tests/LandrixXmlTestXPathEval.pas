{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Tests for the XPath evaluator: the cases in tests/data/xpath (expected
  results from Saxon HE, tools/gen-xpath-testdata.py) evaluated on the
  tree of each folder's document, plus variables and user functions. }

unit LandrixXmlTestXPathEval;

{$I LandrixXml.inc}

interface

procedure Register;

implementation

uses
  SysUtils,
  Classes,
  LandrixXmlBase,
  LandrixXmlXPathTree,
  LandrixXmlXPath,
  LandrixXmlXPathEval,
  LandrixXmlTestFramework;

function U(const S: string): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(S);
end;

function DataFolder(const Name: string): string;
begin
  Result := IncludeTrailingPathDelimiter(RepositoryRoot) + 'tests' + PathDelim + 'data' + PathDelim + 'xpath' +
    PathDelim + Name + PathDelim;
end;

function FileBytes(const FileName: string): TLandrixXmlUtf8;
var
  Stream: TFileStream;
begin
  Result := '';
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, Integer(Stream.Size));
    if Length(Result) > 0 then
      Stream.ReadBuffer(Result[1], Length(Result));
  finally
    Stream.Free;
  end;
end;

{ The lines of a UTF-8 file, as UTF-8. }
function Lines(const FileName: string): TLandrixXmlUtf8Array;
var
  S: TLandrixXmlUtf8;
  I, Start: Integer;
begin
  Result := nil;
  S := FileBytes(FileName);
  Start := 1;
  for I := 1 to Length(S) + 1 do
    if (I > Length(S)) or (S[I] = #10) then
    begin
      if (I > Start) or (I <= Length(S)) then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Copy(S, Start, I - Start);
        if (Length(Result[High(Result)]) > 0) and (Result[High(Result)][Length(Result[High(Result)])] = #13) then
          SetLength(Result[High(Result)], Length(Result[High(Result)]) - 1);
      end;
      Start := I + 1;
    end;
end;

function Esc(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    if (Ord(S[I]) < 32) or (S[I] = '\') then
      Result := Result + U('\x' + IntToHex(Ord(S[I]), 2))
    else
      Result := Result + Copy(S, I, 1);
end;

function AfterSpace(const S: TLandrixXmlUtf8; out Head: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  P: Integer;
begin
  P := 1;
  while (P <= Length(S)) and (S[P] <> ' ') do
    Inc(P);
  Head := Copy(S, 1, P - 1);
  Result := Copy(S, P + 1, MaxInt);
end;

procedure RunFolder(const Name: string);
var
  Cases, Expected: TLandrixXmlUtf8Array;
  Tree: TLandrixXmlXPathTree;
  Context: TLandrixXmlXPathStaticContext;
  Evaluator: TLandrixXmlXPathEvaluator;
  Expr: TLandrixXmlXPathExpression;
  R: TLandrixXmlXPathResult;
  Got, Want: TLandrixXmlUtf8;
  I, K, E, Count, Mismatches: Integer;
  Head, Rest, Prefix: TLandrixXmlUtf8;
  Report: string;
begin
  Cases := Lines(DataFolder(Name) + 'c.txt');
  Expected := Lines(DataFolder(Name) + 'expected.txt');
  Tree := TLandrixXmlXPathTree.Create;
  Context := TLandrixXmlXPathStaticContext.Create;
  { the expected results come from Saxon }
  Context.Profile := xppSaxon;
  Evaluator := TLandrixXmlXPathEvaluator.Create(Tree);
  Mismatches := 0;
  Count := 0;
  Report := '';
  E := 0;
  try
    Tree.LoadFromFile(DataFolder(Name) + 'd.xml');
    for I := 0 to Integer(Length(Cases)) - 1 do
    begin
      Rest := AfterSpace(Cases[I], Head);
      if Head = 'ns' then
      begin
        Rest := AfterSpace(Rest, Prefix);
        Context.AddNamespace(Prefix, Rest);
      end
      else if Head = 'expr' then
      begin
        Inc(Count);
        Got := '';
        try
          Expr := TLandrixXmlXPathExpression.Create(Rest, Context);
          try
            R := Evaluator.Evaluate(Expr, 0);
            try
              for K := 0 to R.Count - 1 do
                if R.Kind[K] = xikNode then
                  Got := Got + 'node ' + Esc(Tree.LocationPathUtf8(R.Node[K])) + #10
                else
                  Got := Got + U(R.TypeName(K)) + ' ' + Esc(R.StringValueUtf8(K)) + #10;
            finally
              R.Free;
            end;
          finally
            Expr.Free;
          end;
        except
          on X: ELandrixXmlXPathError do
            Got := Got + U('error ' + X.XPathCode) + #10;
        end;
        { the expected lines of this case }
        while (E < Length(Expected)) and (Copy(Expected[E], 1, 2) <> '# ') do
          Inc(E);
        Want := '';
        if E < Length(Expected) then
        begin
          Check(Copy(Expected[E], 3, MaxInt) = Rest, Name + ': cases and expected results in the same order');
          Inc(E);
          while (E < Length(Expected)) and (Copy(Expected[E], 1, 2) <> '# ') do
          begin
            if Expected[E] <> '' then
              Want := Want + Expected[E] + #10;
            Inc(E);
          end;
        end;
        if Got <> Want then
        begin
          Inc(Mismatches);
          if Mismatches <= 10 then
            Report := Report + #10 + '  ' + LandrixXmlUtf8ToString(Rest) + #10 + '  saxon: ' +
              LandrixXmlUtf8ToString(Want) + '  got:   ' + LandrixXmlUtf8ToString(Got);
        end;
      end;
    end;
    Check(Count > 0, Name + ': cases present');
    Check(Mismatches = 0, Name + ': ' + IntToStr(Mismatches) + ' of ' + IntToStr(Count) + ' cases differ from Saxon:' +
      Report);
  finally
    Evaluator.Free;
    Context.Free;
    Tree.Free;
  end;
end;

procedure TestSaxonCases;
var
  SR: TSearchRec;
  Names: TStringList;
  I: Integer;
begin
  Names := TStringList.Create;
  try
    if FindFirst(DataFolder('') + '*', faDirectory, SR) = 0 then
    try
      repeat
        if ((SR.Attr and faDirectory) <> 0) and (SR.Name <> '.') and (SR.Name <> '..') and
          FileExists(DataFolder(SR.Name) + 'c.txt') then
          Names.Add(SR.Name);
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
    Names.Sort;
    Check(Names.Count > 0, 'XPath test folders present');
    for I := 0 to Names.Count - 1 do
      RunFolder(Names[I]);
  finally
    Names.Free;
  end;
end;

{ Variables bound by value and lazily, globals and frames, user functions
  with typed parameters. }
procedure TestVariables;
var
  Tree: TLandrixXmlXPathTree;
  Context, FnContext: TLandrixXmlXPathStaticContext;
  Evaluator: TLandrixXmlXPathEvaluator;
  G, L, P: Integer;
  GlobalExpr, LetExpr, Expr, Body: TLandrixXmlXPathExpression;
  Def: TLandrixXmlXPathFunctionDef;
  Functions: TList;
begin
  Tree := TLandrixXmlXPathTree.Create;
  Context := TLandrixXmlXPathStaticContext.Create;
  FnContext := TLandrixXmlXPathStaticContext.Create;
  Evaluator := TLandrixXmlXPathEvaluator.Create(Tree);
  Functions := TList.Create;
  Def := TLandrixXmlXPathFunctionDef.Create;
  GlobalExpr := nil;
  LetExpr := nil;
  Expr := nil;
  Body := nil;
  try
    Tree.LoadFromUtf8(U('<r><a>2</a><a>3</a></r>'));
    G := Context.DeclareVariable(U('total'));
    L := Context.DeclareVariable(U('first'));
    { the function's context: the same globals first, then its parameter }
    FnContext.DeclareVariable(U('total'));
    P := FnContext.DeclareVariable(U('x'));
    FnContext.DeclareFunction(U('urn:f'), U('twice'), 1);
    Context.AddNamespace(U('f'), U('urn:f'));
    Context.DeclareFunction(U('urn:f'), U('twice'), 1);
    Body := TLandrixXmlXPathExpression.Create(U('$x * 2 + $total'), FnContext);
    SetLength(Def.ParamSlots, 1);
    SetLength(Def.ParamTypes, 1);
    Def.ParamSlots[0] := P;
    Def.ParamTypes[0].Declared := True;
    Def.ParamTypes[0].Kind := xtkAtomic;
    Def.ParamTypes[0].AtomicType := xatDecimal;
    Def.ParamTypes[0].Occurrence := xocOne;
    Def.Body := Body;
    Def.FrameSize := FnContext.VariableCount;
    Def.Name := 'f:twice';
    Functions.Add(Def);
    Evaluator.Functions := Functions;
    GlobalExpr := TLandrixXmlXPathExpression.Create(U('sum(//a)'), Context);
    LetExpr := TLandrixXmlXPathExpression.Create(U('for $i in a[1] return $i'), Context);
    Evaluator.SetGlobalCount(1);
    Evaluator.SetFrameSize(Context.VariableCount);
    Evaluator.BindLazy(G, GlobalExpr, 0);
    Evaluator.BindLazy(L, LetExpr, Tree.DocumentElement);
    Expr := TLandrixXmlXPathExpression.Create(U('f:twice($first) = 9 and $total = 5'), Context);
    Check(Evaluator.EvaluateBoolean(Expr, Tree.DocumentElement), 'user function with a global and a lazy let');
    Expr.Free;
    Expr := TLandrixXmlXPathExpression.Create(U('f:twice(1.5)'), Context);
    CheckEqualsUtf8(U('8'), Evaluator.EvaluateString(Expr, Tree.DocumentElement), 'decimal argument plus a double global');
    Expr.Free;
    Expr := TLandrixXmlXPathExpression.Create(U('f:twice(''a'')'), Context);
    try
      Evaluator.EvaluateString(Expr, Tree.DocumentElement);
      FailNotRaised('XPTY0004 for a string argument');
    except
      on X: ELandrixXmlXPathError do
        CheckEqualsStr('XPTY0004', X.XPathCode, 'string for an xs:decimal parameter');
    end;
  finally
    Expr.Free;
    LetExpr.Free;
    GlobalExpr.Free;
    Body.Free;
    Def.Free;
    Functions.Free;
    Evaluator.Free;
    FnContext.Free;
    Context.Free;
    Tree.Free;
  end;
end;

{ Results must not share storage with variables: a union, min() and
  max() once changed the value of the variable they read. }
procedure TestNoAliasing;
var
  Tree: TLandrixXmlXPathTree;
  Context: TLandrixXmlXPathStaticContext;
  Evaluator: TLandrixXmlXPathEvaluator;
  V, W, I: Integer;
  Bound, Data, Expr: TLandrixXmlXPathExpression;

  function RunU(const S: TLandrixXmlUtf8): string;
  begin
    Expr.Free;
    Expr := nil;
    Expr := TLandrixXmlXPathExpression.Create(S, Context);
    Result := LandrixXmlUtf8ToString(Evaluator.EvaluateString(Expr, 0));
  end;

  function Run(const S: string): string;
  begin
    Result := RunU(U(S));
  end;

  { a Cyrillic letter U+04xx as UTF-8 bytes }
  function Cyr(Second: Byte): TLandrixXmlUtf8;
  begin
    Result := '';
    SetLength(Result, 2);
    Result[1] := AnsiChar($D0);
    Result[2] := AnsiChar(Second);
  end;

begin
  Tree := TLandrixXmlXPathTree.Create;
  Context := TLandrixXmlXPathStaticContext.Create;
  Evaluator := TLandrixXmlXPathEvaluator.Create(Tree);
  Bound := nil;
  Data := nil;
  Expr := nil;
  try
    Tree.LoadFromUtf8(U('<r><a>2</a><a>3</a></r>'));
    V := Context.DeclareVariable(U('v'));
    W := Context.DeclareVariable(U('w'));
    Bound := TLandrixXmlXPathExpression.Create(U('//a'), Context);
    Data := TLandrixXmlXPathExpression.Create(U('data(//a)'), Context);
    Evaluator.SetFrameSize(Context.VariableCount);
    Evaluator.BindLazy(V, Bound, 0);
    Evaluator.BindLazy(W, Data, 0);
    for I := 1 to 2 do
    begin
      CheckEqualsStr('3', Run('count($v | /r)'), 'union, round ' + IntToStr(I));
      CheckEqualsStr('2 3', Run('$v'), 'the variable after the union, round ' + IntToStr(I));
      CheckEqualsStr('2', Run('min($w)'), 'min, round ' + IntToStr(I));
      CheckEqualsStr('3', Run('max($w)'), 'max, round ' + IntToStr(I));
      CheckEqualsStr('true', Run('$w = ''3'''), 'the variable stays untypedAtomic, round ' + IntToStr(I));
    end;
    { the regex cache keys by UTF-8 bytes (U+0416 and U+0428 share one
      byte and are no ANSI characters) }
    CheckEqualsStr('true', RunU(U('matches(''') + Cyr($96) + U(''', ''[') + Cyr($96) + U(']'')')),
      'first pattern');
    CheckEqualsStr('false', RunU(U('matches(''') + Cyr($96) + U(''', ''[') + Cyr($A8) + U(']'')')),
      'second pattern, differing only in a non-ANSI letter');
  finally
    Expr.Free;
    Data.Free;
    Bound.Free;
    Evaluator.Free;
    Context.Free;
    Tree.Free;
  end;
end;

{ The values kept for context-free subexpressions, and "//" evaluated as
  descendant: positional predicates keep their meaning, the focus,
  current() and rebound globals are not kept. }
procedure TestKeptValues;
var
  Tree: TLandrixXmlXPathTree;
  Context: TLandrixXmlXPathStaticContext;
  Evaluator: TLandrixXmlXPathEvaluator;
  N, B, A: Integer;
  Expr, One, Two: TLandrixXmlXPathExpression;
  S: TLandrixXmlXPathSequence;

  function Run(const S: string; Node: Integer): string;
  begin
    Expr.Free;
    Expr := nil;
    Expr := TLandrixXmlXPathExpression.Create(U(S), Context);
    Result := LandrixXmlUtf8ToString(Evaluator.EvaluateString(Expr, Node));
  end;

  function Again(Node: Integer): string;
  begin
    Result := LandrixXmlUtf8ToString(Evaluator.EvaluateString(Expr, Node));
  end;

begin
  Tree := TLandrixXmlXPathTree.Create;
  Context := TLandrixXmlXPathStaticContext.Create;
  Evaluator := TLandrixXmlXPathEvaluator.Create(Tree);
  Expr := nil;
  One := nil;
  S := LandrixXmlXPathEmpty;
  Two := nil;
  try
    Tree.LoadFromUtf8(U('<r><a k="1"><a k="2"/></a><b><a k="3"/><a k="4"/></b></r>'));
    N := Context.DeclareVariable(U('n'));
    One := TLandrixXmlXPathExpression.Create(U('1'), nil);
    Two := TLandrixXmlXPathExpression.Create(U('2'), nil);
    Evaluator.SetGlobalCount(1);
    CheckEqualsStr('1 2 3', Run('//a[1]/@k', 0), '//a[1] is the first a of each parent');
    CheckEqualsStr('1 2 4', Run('//a[last()]/@k', 0), '//a[last()]');
    CheckEqualsStr('4', Run('//a[position() = 2]/@k', 0), '//a[position() = 2]');
    CheckEqualsStr('2 3 4', Run('//a[@k > 1]/@k', 0), 'a predicate without position');
    CheckEqualsStr('3', Run('(//a)[3]/@k', 0), '(//a)[3]');
    CheckEqualsStr('2 4', Run('/r//a[2]/@k | //b/a[2]/@k | //a/a/@k', 0), 'a relative //');
    { a global used as a position, kept until it is bound again }
    Evaluator.BindValue(N, LandrixXmlXPathStringItem(U('2')));
    CheckEqualsStr('1 2 3 4', Run('//a[$n]/@k', 0), 'a string predicate is true');
    Evaluator.BindLazy(N, Two, 0);
    CheckEqualsStr('4', Again(0), 'the number 2, after binding the global again');
    Evaluator.BindLazy(N, One, 0);
    CheckEqualsStr('1 2 3', Again(0), 'the number 1');
    { the focus and current() are never kept }
    B := Tree.NextSibling[Tree.FirstChild(Tree.DocumentElement)];
    A := Tree.FirstChild(B);
    CheckEqualsStr('1', Run('count(a)', Tree.DocumentElement), 'count(a) on r');
    CheckEqualsStr('2', Again(B), 'count(a) on b');
    CheckEqualsStr('r', Run('name()', Tree.DocumentElement), 'name() on r');
    CheckEqualsStr('b', Again(B), 'name() on b');
    Evaluator.CurrentNode := A;
    CheckEqualsStr('3', Run('string(current()/@k)', 0), 'current() on the first a of b');
    Evaluator.CurrentNode := Tree.NextSibling[A];
    CheckEqualsStr('4', Again(0), 'current() on the second');
    { the variables of for, some and every are never global, even when
      their slots are below GlobalCount (no static context) }
    Expr.Free;
    Expr := nil;
    Expr := TLandrixXmlXPathExpression.Create(U('for $i in a return string($i/@k)'), nil);
    CheckEqualsStr('3 4', LandrixXmlUtf8ToString(Evaluator.EvaluateString(Expr, B)), 'for over two a');
    { a caller changing a result does not change what is kept }
    Expr.Free;
    Expr := nil;
    Expr := TLandrixXmlXPathExpression.Create(U('concat(''a'', ''b'')'), nil);
    S := Evaluator.EvaluateSequence(Expr, 0);
    S.Items[0].Text := U('changed');
    CheckEqualsStr('ab', Again(0), 'the kept value after the caller changed its copy');
    Expr.Free;
    Expr := nil;
    Expr := TLandrixXmlXPathExpression.Create(U('(1 + 1, xs:time(''10:00:30''))'), nil);
    S := Evaluator.EvaluateSequence(Expr, 0);
    S.Items[0].Decimal.Limbs[0] := 9;
    S.Items[1].DateTime.Second.Limbs[0] := 9;
    CheckEqualsStr('2 10:00:30', Again(0), 'kept numbers and dates after the caller changed its digits');
    { a kept value belongs to the tree as it was }
    CheckEqualsStr('4', Run('count(//a)', 0), 'four a');
    Tree.LoadFromUtf8(U('<r><a/></r>'));
    Evaluator.ClearCache;
    CheckEqualsStr('1', Again(0), 'one a after loading again and ClearCache');
  finally
    Expr.Free;
    Two.Free;
    One.Free;
    Evaluator.Free;
    Context.Free;
    Tree.Free;
  end;
end;

{ EvaluatePattern: an error in a predicate of the pattern's steps drops
  the item; errors further inside are not caught there. }
procedure TestPatterns;
var
  Tree: TLandrixXmlXPathTree;
  Evaluator: TLandrixXmlXPathEvaluator;
  Expr, Bound: TLandrixXmlXPathExpression;
  Context: TLandrixXmlXPathStaticContext;
  Raised: string;

  function Count(const S: string): Integer;
  begin
    Expr.Free;
    Expr := nil;
    Expr := TLandrixXmlXPathExpression.Create(U(S), nil);
    Result := Evaluator.EvaluatePattern(Expr, 0).Count;
  end;

begin
  Tree := TLandrixXmlXPathTree.Create;
  Evaluator := TLandrixXmlXPathEvaluator.Create(Tree);
  Context := TLandrixXmlXPathStaticContext.Create;
  Expr := nil;
  Bound := nil;
  try
    Context.DeclareVariable(U('v'));
    Tree.LoadFromUtf8(U('<r><a><v>1</v></a><a><v>1</v><v>2</v></a><a><v>x</v></a></r>'));
    CheckEquals(1, Count('//a[normalize-space(v) = ''1'']'), 'the a with two v does not match');
    CheckEquals(3, Count('//a[xs:integer(v[1]) > 0]/v'), 'the steps after a dropped item');
    CheckEquals(3, Count('//a[normalize-space(v[1]) = ''1''] | //a[v = ''x'']'), 'both branches');
    CheckEquals(1, Count('//a[normalize-space(v) = ''1''] | //a[xs:integer(v[1]) > 0]'), 'each fails on one a');
    { as Saxon: a node the first branch failed on does not match the second }
    CheckEquals(2, Count('//a[xs:integer(v[1]) > 0] | //a[normalize-space(v) = ''x'']'), 'failed in the first branch');
    CheckEquals(0, Count('//r[count(a[xs:integer(v[1]) > 0]) = 2]'), 'an error in a nested predicate drops r');
    { a position counts the failed item: as Saxon, nothing matches }
    CheckEquals(0, Count('//a[xs:integer(v[1]) > 0][last()]'), 'last() after an error');
    CheckEquals(1, Count('//a[xs:integer(v[1]) = position()]'), 'a position in the failing predicate itself');
    CheckEquals(2, Count('//a[xs:integer(v[1]) > 0][v[last()]]'), 'last() of a nested focus');
    CheckEquals(2, Count('//a[xs:integer(v[1]) > 0][if (v) then true() else false()]'), 'a boolean if');
    CheckEquals(0, Count('//(a[xs:integer(v[1]) > 0])[last()]'), 'a filter on a failed path');
    CheckEquals(2, Count('//a[xs:integer(v[1]) > 0][xs:boolean(''true'')]'), 'a boolean constructor');
    CheckEquals(2, Count('//a[xs:integer(v[1]) > 0][(v)[last()]]'), 'a filter of nodes');
    CheckEquals(2, Count('//a[xs:integer(v[1]) > 0][substring(v[1], 1)]'), 'a string function');
    CheckEquals(1, Count('//a[xs:integer(v[1]) > 0][string-length(v[1])]'), 'a number: items before the error');
    CheckEquals(1, Count('//a[xs:integer(v[1]) > 0][1]'), 'the first item comes before the error');
    CheckEquals(1, Count('//a[xs:integer(v[1]) > 0][2]'), 'the second item comes before the error');
    CheckEquals(0, Count('//a[xs:integer(v[1]) > 0][3]'), 'the third item is the failed one');
    CheckEquals(1, Count('//a[xs:integer(v[1]) > 0][1][last()]'), 'last() after a [1] before the error');
    CheckEquals(2, Count('//a[normalize-space(v) != ''z''][reverse(v)]'), 'reverse() of nodes');
    CheckEquals(2, Count('//a[xs:integer(v[1]) > 0][.]'), 'the context node');
    CheckEquals(1, Count('//a[xs:integer(v[1]) > 0][xs:integer(1)][last()]'), 'xs:integer(1) as [1]');
    CheckEquals(1, Count('//(a[xs:integer(v[1]) > 0][1])[last()]'), 'a filter after a resolved [1]');
    CheckEquals(1, Count('//((a[xs:integer(v[1]) > 0])[1])[last()]'), 'a nested filter after a resolved [1]');
    CheckEquals(1, Count('//(a[xs:integer(v[1]) > 0])[1]'), 'a filter: the first item comes before the error');
    { what is not supported is not "no match" }
    Raised := '';
    try
      Count('//a[matches(v[1], ''[a-z]'', ''i'')]');
    except
      on E: ELandrixXmlXPathError do
        Raised := E.XPathCode;
    end;
    CheckEqualsStr('FOER0000', Raised, 'an unsupported regex flag');
    Count('//r[count(a[xs:integer(v[1]) > 0]) = 2]');
    Raised := '';
    try
      Evaluator.EvaluateSequence(Expr, 0);
    except
      on E: ELandrixXmlXPathError do
        Raised := E.XPathCode;
    end;
    CheckEqualsStr('FORG0001', Raised, 'the same path as an expression');
    { a variable read in a pattern keeps its value as an expression }
    Evaluator.SetGlobalCount(1);
    Bound := TLandrixXmlXPathExpression.Create(U('//a[xs:integer(v[1]) > 0]'), nil);
    Evaluator.BindLazy(0, Bound, 0);
    Expr.Free;
    Expr := nil;
    Expr := TLandrixXmlXPathExpression.Create(U('$v'), Context);
    Raised := '';
    try
      Evaluator.EvaluatePattern(Expr, 0);
    except
      on E: ELandrixXmlXPathError do
        Raised := E.XPathCode;
    end;
    CheckEqualsStr('FORG0001', Raised, 'the variable in a pattern');
    { a nested filter whose error is caught keeps the failure seen before }
    Tree.LoadFromUtf8(U('<r><a k="bad"/><a k="1"/><a k="2"/></r>'));
    Evaluator.ClearCache;
    CheckEquals(0, Count('//(a[if (@k = ''bad'') then xs:integer(@k) > 0 else ' +
      '(((xs:integer(concat(@k, ''x'')))[1] = 0) or true())])[1]'), 'the failure before a caught error');
  finally
    Expr.Free;
    Bound.Free;
    Context.Free;
    Evaluator.Free;
    Tree.Free;
  end;
end;

{ AddDocument and document(): one numbering over two trees, the names,
  roots and kept values of each tree. }
procedure TestDocuments;
var
  Tree, Codes: TLandrixXmlXPathTree;
  Evaluator: TLandrixXmlXPathEvaluator;
  Expr: TLandrixXmlXPathExpression;
  R: TLandrixXmlXPathResult;
  Raised: string;

  function Run(const S: string; Node: Integer): string;
  begin
    Expr.Free;
    Expr := nil;
    Expr := TLandrixXmlXPathExpression.Create(U(S), nil);
    Result := LandrixXmlUtf8ToString(Evaluator.EvaluateString(Expr, Node));
  end;

  function Again(Node: Integer): string;
  begin
    Result := LandrixXmlUtf8ToString(Evaluator.EvaluateString(Expr, Node));
  end;

begin
  Tree := TLandrixXmlXPathTree.Create;
  Codes := TLandrixXmlXPathTree.Create;
  Evaluator := TLandrixXmlXPathEvaluator.Create(Tree);
  Expr := nil;
  R := nil;
  try
    Tree.LoadFromUtf8(U('<r><a k="1"/><a k="2"/></r>'));
    { other names first: the expanded-name ids of the two trees differ }
    Codes.LoadFromUtf8(U('<codes><c v="1"/><c v="3"/><a k="x"/></codes>'));
    Evaluator.AddDocument(U('codes.xml'), Codes);
    CheckEqualsStr('2', Run('count(document(''codes.xml'')/codes/c)', 0), 'the code list');
    CheckEqualsStr('x', Run('string(document(''codes.xml'')//a/@k)', 0), 'a name of both trees');
    CheckEqualsStr('1', Run('//a[@k = document(''codes.xml'')/codes/c/@v]/@k', 0), 'a comparison across trees');
    CheckEqualsStr('codes', Run('name(document(''codes.xml'')/codes/c[1]/root()/*)', 0), 'root() of a code');
    CheckEqualsStr('2', Run('count(document(''codes.xml'')/codes/c[/codes])', 0), '"/" on a code');
    CheckEqualsStr('0', Run('count(//a[/codes])', 0), '"/" in the document');
    CheckEqualsStr('r codes', Run('for $n in (document(''codes.xml'')/codes | /r) return name($n)', 0),
      'document order: the document first');
    { a rooted path is kept for the document's root only }
    CheckEqualsStr('1', Run('count(/r)', 0), '/r from the document');
    CheckEqualsStr('0', Again(Tree.Count), '/r from the root of the code list');
    CheckEqualsStr('1', Again(1), '/r from the document again');
    CheckEqualsStr('3', Run('string(document(''codes.xml'')/codes/c[2]/@v)', 0), 'the string of a code');
    Expr.Free;
    Expr := nil;
    Expr := TLandrixXmlXPathExpression.Create(U('document(''codes.xml'')/codes/c[2]/@v'), nil);
    R := Evaluator.Evaluate(Expr, 0);
    CheckEquals(1, R.Count, 'one attribute');
    CheckEqualsStr('3', LandrixXmlUtf8ToString(R.StringValueUtf8(0)), 'its string in the result');
    Check(R.Node[0] >= Tree.Count, 'a node number after the document''s');
    Raised := '';
    try
      Run('document(''other.xml'')', 0);
    except
      on E: ELandrixXmlXPathError do
        Raised := E.XPathCode;
    end;
    CheckEqualsStr('FODC0002', Raised, 'an unknown document');
  finally
    R.Free;
    Expr.Free;
    Evaluator.Free;
    Codes.Free;
    Tree.Free;
  end;
end;

{ The fields of a line separated by tabs. }
function Fields(const S: TLandrixXmlUtf8): TLandrixXmlUtf8Array;
var
  I, Start: Integer;
begin
  Result := nil;
  Start := 1;
  for I := 1 to Length(S) + 1 do
    if (I > Length(S)) or (S[I] = #9) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Copy(S, Start, I - Start);
      Start := I + 1;
    end;
end;

{ The result of Text in a profile: "TYPE VALUE" per item (" | " between
  items) or "error CODE". }
function ProfileResult(const Text: TLandrixXmlUtf8; Profile: TLandrixXmlXPathProfile;
  Evaluator: TLandrixXmlXPathEvaluator): TLandrixXmlUtf8;
var
  Context: TLandrixXmlXPathStaticContext;
  Expr: TLandrixXmlXPathExpression;
  R: TLandrixXmlXPathResult;
  K: Integer;
begin
  Result := '';
  Context := TLandrixXmlXPathStaticContext.Create;
  Expr := nil;
  try
    Context.Profile := Profile;
    try
      Expr := TLandrixXmlXPathExpression.Create(Text, Context);
      R := Evaluator.Evaluate(Expr, 0);
      try
        for K := 0 to R.Count - 1 do
        begin
          if K > 0 then
            Result := Result + ' | ';
          Result := Result + U(R.TypeName(K)) + ' ' + R.StringValueUtf8(K);
        end;
      finally
        R.Free;
      end;
    except
      on X: ELandrixXmlXPathError do
        Result := U('error ' + X.XPathCode);
    end;
  finally
    Expr.Free;
    Context.Free;
  end;
end;

{ tests/data/xpath/profiles.txt: each row in both profiles; a row that
  does not differ is an error of the table. }
procedure TestProfiles;
var
  Rows, F: TLandrixXmlUtf8Array;
  Tree: TLandrixXmlXPathTree;
  Evaluator: TLandrixXmlXPathEvaluator;
  I, Count: Integer;
  Where: string;
begin
  F := nil;
  Rows := Lines(IncludeTrailingPathDelimiter(RepositoryRoot) + 'tests' + PathDelim + 'data' + PathDelim + 'xpath' +
    PathDelim + 'profiles.txt');
  Tree := TLandrixXmlXPathTree.Create;
  Evaluator := nil;
  Count := 0;
  try
    Tree.LoadFromUtf8('<r/>');
    Evaluator := TLandrixXmlXPathEvaluator.Create(Tree);
    for I := 0 to Integer(Length(Rows)) - 1 do
      if (Rows[I] <> '') and (Rows[I][1] <> '#') then
      begin
        F := Fields(Rows[I]);
        Where := LandrixXmlUtf8ToString(F[0]);
        Check(Length(F) = 4, Where + ': four fields');
        if Length(F) <> 4 then
          Continue;
        Inc(Count);
        Check(F[1] <> F[2], Where + ': the profiles differ');
        CheckEqualsUtf8(F[1], ProfileResult(F[0], xppXPath20, Evaluator), Where + ' (XPath 2.0)');
        CheckEqualsUtf8(F[2], ProfileResult(F[0], xppSaxon, Evaluator), Where + ' (Saxon)');
      end;
    Check(Count >= 10, 'rows present');
  finally
    Evaluator.Free;
    Tree.Free;
  end;
end;

{ The declared types of a user function convert in the function's
  profile, not in the caller's: f:inf() returns xs:untypedAtomic('+INF')
  as an xs:double, f:id($x as xs:double) returns $x; an xs:anyURI made in
  the Saxon profile stays as it is when cast to xs:anyURI in XPath 2.0
  (f:uri() returns xs:anyURI('%gg')). }
procedure TestMixedProfiles;

  procedure Run(FnProfile, CallerProfile: TLandrixXmlXPathProfile; const Call, Want: string);
  var
    Tree: TLandrixXmlXPathTree;
    Context, FnContext: TLandrixXmlXPathStaticContext;
    Evaluator: TLandrixXmlXPathEvaluator;
    Body, IdBody, UriBody, Expr: TLandrixXmlXPathExpression;
    Def, IdDef, UriDef: TLandrixXmlXPathFunctionDef;
    Functions: TList;
    Got: string;
    P: Integer;
  begin
    Tree := TLandrixXmlXPathTree.Create;
    Context := TLandrixXmlXPathStaticContext.Create;
    FnContext := TLandrixXmlXPathStaticContext.Create;
    Evaluator := TLandrixXmlXPathEvaluator.Create(Tree);
    Functions := TList.Create;
    Def := TLandrixXmlXPathFunctionDef.Create;
    IdDef := TLandrixXmlXPathFunctionDef.Create;
    UriDef := TLandrixXmlXPathFunctionDef.Create;
    Body := nil;
    IdBody := nil;
    UriBody := nil;
    Expr := nil;
    try
      Tree.LoadFromUtf8(U('<r/>'));
      FnContext.Profile := FnProfile;
      Context.Profile := CallerProfile;
      P := FnContext.DeclareVariable(U('x'));
      Context.AddNamespace(U('f'), U('urn:f'));
      Context.DeclareFunction(U('urn:f'), U('inf'), 0);
      Context.DeclareFunction(U('urn:f'), U('id'), 1);
      Context.DeclareFunction(U('urn:f'), U('uri'), 0);
      Body := TLandrixXmlXPathExpression.Create(U('xs:untypedAtomic(''+INF'')'), FnContext);
      IdBody := TLandrixXmlXPathExpression.Create(U('$x'), FnContext);
      UriBody := TLandrixXmlXPathExpression.Create(U('xs:anyURI(''%gg'')'), FnContext);
      UriDef.Body := UriBody;
      UriDef.FrameSize := FnContext.VariableCount;
      UriDef.Name := 'f:uri';
      Def.Body := Body;
      Def.ResultType.Declared := True;
      Def.ResultType.Kind := xtkAtomic;
      Def.ResultType.AtomicType := xatDouble;
      Def.ResultType.Occurrence := xocOne;
      Def.FrameSize := FnContext.VariableCount;
      Def.Name := 'f:inf';
      SetLength(IdDef.ParamSlots, 1);
      SetLength(IdDef.ParamTypes, 1);
      IdDef.ParamSlots[0] := P;
      IdDef.ParamTypes[0] := Def.ResultType;
      IdDef.Body := IdBody;
      IdDef.FrameSize := FnContext.VariableCount;
      IdDef.Name := 'f:id';
      Functions.Add(Def);
      Functions.Add(IdDef);
      Functions.Add(UriDef);
      Evaluator.Functions := Functions;
      Evaluator.SetFrameSize(Context.VariableCount);
      try
        Expr := TLandrixXmlXPathExpression.Create(U(Call), Context);
        Got := LandrixXmlUtf8ToString(Evaluator.EvaluateString(Expr, 0));
      except
        on X: ELandrixXmlXPathError do
          Got := 'error ' + X.XPathCode;
      end;
      CheckEqualsStr(Want, Got, Call + ', function ' + IntToStr(Ord(FnProfile)) + ', caller ' +
        IntToStr(Ord(CallerProfile)));
    finally
      Expr.Free;
      UriBody.Free;
      IdBody.Free;
      Body.Free;
      UriDef.Free;
      IdDef.Free;
      Def.Free;
      Functions.Free;
      Evaluator.Free;
      FnContext.Free;
      Context.Free;
      Tree.Free;
    end;
  end;

begin
  Run(xppSaxon, xppXPath20, 'string(f:inf())', 'INF');
  Run(xppXPath20, xppSaxon, 'string(f:inf())', 'error FORG0001');
  Run(xppSaxon, xppXPath20, 'string(f:id(xs:untypedAtomic(''+INF'')))', 'INF');
  Run(xppXPath20, xppSaxon, 'string(f:id(xs:untypedAtomic(''+INF'')))', 'error FORG0001');
  Run(xppSaxon, xppXPath20, 'string(xs:anyURI(f:uri()))', '%gg');
  Run(xppSaxon, xppXPath20, 'string(f:uri() castable as xs:anyURI)', 'true');
  Run(xppXPath20, xppSaxon, 'string(f:uri())', 'error FORG0001');
end;

procedure Register;
begin
  RegisterTest('XPathEval.SaxonCases', TestSaxonCases);
  RegisterTest('XPathEval.MixedProfiles', TestMixedProfiles);
  RegisterTest('XPathEval.Profiles', TestProfiles);
  RegisterTest('XPathEval.Variables', TestVariables);
  RegisterTest('XPathEval.NoAliasing', TestNoAliasing);
  RegisterTest('XPathEval.KeptValues', TestKeptValues);
  RegisterTest('XPathEval.Patterns', TestPatterns);
  RegisterTest('XPathEval.Documents', TestDocuments);
end;

end.
