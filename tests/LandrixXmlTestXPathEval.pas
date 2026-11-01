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
  LandrixXmlDecimal,
  LandrixXmlXsdTypes,
  LandrixXmlReader,
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

{ The cases of Folder (c.txt, d.xml) in Profile against the results in
  the file ExpectedName, which Source (Saxon, an oracle) computed. }
procedure RunCases(const Folder, Name, ExpectedName, Source: string; Profile: TLandrixXmlXPathProfile);
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
  Cases := Lines(Folder + 'c.txt');
  Expected := Lines(Folder + ExpectedName);
  Tree := TLandrixXmlXPathTree.Create;
  Context := TLandrixXmlXPathStaticContext.Create;
  Context.Profile := Profile;
  Evaluator := TLandrixXmlXPathEvaluator.Create(Tree);
  Mismatches := 0;
  Count := 0;
  Report := '';
  E := 0;
  try
    Tree.LoadFromFile(Folder + 'd.xml');
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
            Report := Report + #10 + '  ' + LandrixXmlUtf8ToString(Rest) + #10 + '  ' + Source + ': ' +
              LandrixXmlUtf8ToString(Want) + '  got:   ' + LandrixXmlUtf8ToString(Got);
        end;
      end;
    end;
    Check(Count > 0, Name + ': cases present');
    Check(Mismatches = 0, Name + ': ' + IntToStr(Mismatches) + ' of ' + IntToStr(Count) + ' cases differ from ' +
      Source + ':' + Report);
  finally
    Evaluator.Free;
    Context.Free;
    Tree.Free;
  end;
end;

{ a folder of tests/data/xpath: the expected results come from Saxon }
procedure RunFolder(const Name: string);
begin
  RunCases(DataFolder(Name), Name, 'expected.txt', 'saxon', xppSaxon);
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

{ tests/data/xpath-oracle/durations and dates: generated cases with the
  results of independent oracles (tools/gen-duration-testdata.py,
  tools/gen-date-testdata.py) for both profiles. }
procedure TestOracleCases;
var
  Folder: string;
begin
  Folder := IncludeTrailingPathDelimiter(RepositoryRoot) + 'tests' + PathDelim + 'data' + PathDelim +
    'xpath-oracle' + PathDelim + 'durations' + PathDelim;
  RunCases(Folder, 'durations', 'expected.txt', 'oracle', xppXPath20);
  RunCases(Folder, 'durations (Saxon)', 'expected-saxon.txt', 'oracle', xppSaxon);
  Folder := IncludeTrailingPathDelimiter(RepositoryRoot) + 'tests' + PathDelim + 'data' + PathDelim +
    'xpath-oracle' + PathDelim + 'dates' + PathDelim;
  RunCases(Folder, 'dates', 'expected.txt', 'oracle', xppXPath20);
  RunCases(Folder, 'dates (Saxon)', 'expected-saxon.txt', 'oracle', xppSaxon);
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
    Def.ParamTypes[0].AtomicType := xikDecimal;
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

{ The kind tests of sequence types on a parameter: f:id($x) with $x of
  the declared type, called with an argument; XPTY0004 if it does not
  match. }
procedure TestSequenceTypeMatching;
var
  Tree: TLandrixXmlXPathTree;
  Context, FnContext: TLandrixXmlXPathStaticContext;
  Evaluator: TLandrixXmlXPathEvaluator;
  Body: TLandrixXmlXPathExpression;
  Def: TLandrixXmlXPathFunctionDef;
  Functions: TList;

  procedure CheckMatch(const TypeText, Arg: string; Matches: Boolean);
  var
    Expr: TLandrixXmlXPathExpression;
    Ok: Boolean;
    Msg: string;
  begin
    Def.ParamTypes[0] := LandrixXmlXPathParseSequenceType(U(TypeText), FnContext);
    Expr := TLandrixXmlXPathExpression.Create(U('count(f:id(' + Arg + '))'), Context);
    try
      Ok := False;
      Msg := '';
      try
        Evaluator.EvaluateString(Expr, 0);
        Ok := True;
      except
        on X: ELandrixXmlXPathError do
        begin
          Msg := X.Message;
          CheckEqualsStr('XPTY0004', X.XPathCode, TypeText + ' for ' + Arg + ': ' + Msg);
        end;
      end;
      CheckEquals(Ord(Matches), Ord(Ok), TypeText + ' for ' + Arg + ' ' + Msg);
    finally
      Expr.Free;
    end;
  end;

begin
  Tree := TLandrixXmlXPathTree.Create;
  Context := TLandrixXmlXPathStaticContext.Create;
  FnContext := TLandrixXmlXPathStaticContext.Create;
  Evaluator := TLandrixXmlXPathEvaluator.Create(Tree);
  Functions := TList.Create;
  Def := TLandrixXmlXPathFunctionDef.Create;
  Body := nil;
  try
    Tree.LoadFromUtf8(U('<r xmlns:p="urn:p"><a k="1" p:k="2">t<!--c--><?pi x?></a><p:b/></r>'));
    FnContext.AddNamespace(U('p'), U('urn:p'));
    SetLength(Def.ParamSlots, 1);
    SetLength(Def.ParamTypes, 1);
    Def.ParamSlots[0] := FnContext.DeclareVariable(U('x'));
    Body := TLandrixXmlXPathExpression.Create(U('$x'), FnContext);
    Def.Body := Body;
    Def.FrameSize := FnContext.VariableCount;
    Def.Name := 'f:id';
    Functions.Add(Def);
    Context.AddNamespace(U('f'), U('urn:f'));
    Context.DeclareFunction(U('urn:f'), U('id'), 1);
    Evaluator.Functions := Functions;
    Evaluator.SetFrameSize(Context.VariableCount);
    CheckMatch('node()', '/r/a/@k', True);
    CheckMatch('xs:gYear', 'xs:gYear(''2024'')', True);
    CheckMatch('xs:gYear', 'xs:untypedAtomic(''2024'')', True);
    CheckMatch('xs:gYear', 'xs:gMonth(''--01'')', False);
    CheckMatch('xs:gYear', '''2024''', False);
    CheckMatch('xs:gMonthDay*', '(xs:gMonthDay(''--02-29''), xs:gMonthDay(''--03-01''))', True);
    CheckMatch('xs:float', 'xs:float(1)', True);
    CheckMatch('xs:float', '1.5', True);
    CheckMatch('xs:float', 'xs:double(1)', False);
    CheckMatch('xs:QName', 'xs:QName(''xml:lang'')', True);
    CheckMatch('xs:QName', 'xs:untypedAtomic(''a'')', False);
    CheckMatch('xs:QName', '''xml:lang''', False);
    CheckMatch('element()', '/r/a', True);
    CheckMatch('element()', '/r/a/text()', False);
    CheckMatch('element()', '/r/a/@k', False);
    CheckMatch('element(a)', '/r/a', True);
    CheckMatch('element(a)', '/r/*[2]', False);
    CheckMatch('element(p:b)', '/r/*[2]', True);
    CheckMatch('element(b)', '/r/*[2]', False);
    CheckMatch('element(*, xs:untyped)', '/r/a', True);
    CheckMatch('element(*, xs:anyType)', '/r/a', True);
    CheckMatch('element(a, xs:string)', '/r/a', False);
    CheckMatch('element(a, xs:untypedAtomic)', '/r/a', False);
    CheckMatch('attribute()', '/r/a/@k', True);
    CheckMatch('attribute()', '/r/a', False);
    CheckMatch('attribute(k)', '/r/a/@k', True);
    CheckMatch('attribute(p:k)', '/r/a/@*[2]', True);
    CheckMatch('attribute(k)', '/r/a/@*[2]', False);
    CheckMatch('attribute(*, xs:untypedAtomic)', '/r/a/@k', True);
    CheckMatch('attribute(*, xs:anyAtomicType)', '/r/a/@k', True);
    CheckMatch('attribute(*, xs:anySimpleType)', '/r/a/@k', True);
    CheckMatch('attribute(*, xs:anyType)', '/r/a/@k', True);
    CheckMatch('attribute(*, xs:untyped)', '/r/a/@k', False);
    CheckMatch('attribute(*, xs:string)', '/r/a/@k', False);
    CheckMatch('text()', '/r/a/text()', True);
    CheckMatch('text()', '/r/a/comment()', False);
    CheckMatch('comment()', '/r/a/comment()', True);
    CheckMatch('processing-instruction()', '/r/a/processing-instruction()', True);
    CheckMatch('processing-instruction(pi)', '/r/a/processing-instruction()', True);
    CheckMatch('processing-instruction(''pi'')', '/r/a/processing-instruction()', True);
    CheckMatch('processing-instruction(other)', '/r/a/processing-instruction()', False);
    CheckMatch('document-node()', '/', True);
    CheckMatch('document-node()', '/r', False);
    CheckMatch('document-node(element(r))', '/', True);
    CheckMatch('document-node(element())', '/', True);
    CheckMatch('document-node(element(a))', '/', False);
    CheckMatch('document-node(element(r, xs:untyped))', '/', True);
    CheckMatch('node()*', '/r/a/node()', True);
    CheckMatch('element()', '/r/*', False);
    CheckMatch('element()+', '()', False);
    CheckMatch('element()?', '()', True);
    CheckMatch('empty-sequence()', '()', True);
    CheckMatch('empty-sequence()', '/r', False);
    CheckMatch('empty-sequence()', '1', False);
    CheckMatch('element()', '1', False);
  finally
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
    S.Items[0].Bits := 9;
    S.Items[1].Text := U('11:00:00');
    CheckEqualsStr('2 10:00:30', Again(0), 'kept numbers and dates after the caller changed its items');
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
    CheckEquals(1, Count('//a[xs:integer(v[1]) > 0][1 treat as xs:integer][last()]'), 'treat as around [1]');
    CheckEquals(1, Count('//(a[xs:integer(v[1]) > 0][1])[last()]'), 'a filter after a resolved [1]');
    CheckEquals(1, Count('//((a[xs:integer(v[1]) > 0])[1])[last()]'), 'a nested filter after a resolved [1]');
    CheckEquals(1, Count('//(a[xs:integer(v[1]) > 0])[1]'), 'a filter: the first item comes before the error');
    { fn:error is an error of the rules: no match, also with FOER0000 }
    CheckEquals(0, Count('//a[error()]'), 'error() in a predicate');
    CheckEquals(0, Count('//a[error() or false()]'), 'error() before or');
    CheckEquals(0, Count('//a[error() and true()]'), 'error() before and');
    CheckEquals(1, Count('//a[if (v = ''x'') then error(QName(''urn:e'', ''E'')) else v = 2]'), 'error(QName) for one a');
    { what is beyond the limits is not "no match" }
    Raised := '';
    try
      Count('//a[matches(v[1], ''(ab){100000}'')]');
    except
      on E: ELandrixXmlXPathError do
        Raised := E.XPathCode;
    end;
    CheckEqualsStr('FOER0000', Raised, 'a regular expression beyond the limits');
    Raised := '';
    try
      Count('//a except //a[xs:integer(v[1]) > 0]');
    except
      on E: ELandrixXmlXPathError do
        Raised := E.XPathCode;
    end;
    CheckEqualsStr('FOER0000', Raised, 'except in a pattern');
    { inside a predicate the operators are ordinary expressions }
    CheckEquals(1, Count('//a[v intersect v[2]]'), 'intersect in a predicate');
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
    { fn:error in a variable: no match on every node, also when the
      stored error is raised again }
    Bound.Free;
    Bound := nil;
    Bound := TLandrixXmlXPathExpression.Create(U('error()'), nil);
    Evaluator.BindLazy(0, Bound, 0);
    Expr.Free;
    Expr := nil;
    Expr := TLandrixXmlXPathExpression.Create(U('//a[$v]'), Context);
    CheckEquals(0, Evaluator.EvaluatePattern(Expr, 0).Count, 'error() in a variable');
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

{ deep-equal across two trees and on documents nested deeper than the
  stack would allow for one call per level. }
procedure TestDeepEqual;
const
  Levels = 17;
var
  Tree, Other: TLandrixXmlXPathTree;
  Evaluator: TLandrixXmlXPathEvaluator;
  Expr: TLandrixXmlXPathExpression;
  Reader: TLandrixXmlReader;
  Open, Close: TLandrixXmlUtf8;
  I: Integer;

  function Run(const S: string): string;
  begin
    Expr.Free;
    Expr := nil;
    Expr := TLandrixXmlXPathExpression.Create(U(S), nil);
    Result := LandrixXmlUtf8ToString(Evaluator.EvaluateString(Expr, 0));
  end;

  procedure Load(T: TLandrixXmlXPathTree; const Text: TLandrixXmlUtf8);
  begin
    Reader := TLandrixXmlReader.Create;
    try
      Reader.MaxDepth := 1 shl (Levels + 1);
      Reader.LoadFromUtf8(Text);
      T.LoadFromReader(Reader);
    finally
      Reader.Free;
      Reader := nil;
    end;
  end;

begin
  Tree := TLandrixXmlXPathTree.Create;
  Other := TLandrixXmlXPathTree.Create;
  Evaluator := TLandrixXmlXPathEvaluator.Create(Tree);
  Expr := nil;
  Reader := nil;
  try
    { 2^17 nested elements }
    Open := U('<a>');
    Close := U('</a>');
    for I := 1 to Levels do
    begin
      Open := Open + Open;
      Close := Close + Close;
    end;
    Load(Tree, Open + U('x') + Close);
    Load(Other, Open + U('y') + Close);
    Evaluator.AddDocument(U('other.xml'), Other);
    CheckEqualsStr('true', Run('deep-equal(/, /)'), 'a deep document equals itself');
    CheckEqualsStr('false', Run('deep-equal(/, document(''other.xml''))'), 'the innermost text differs');
    CheckEqualsStr('false', Run('deep-equal(/a/a, document(''other.xml'')/a/a/a)'), 'one level less');
  finally
    Expr.Free;
    Evaluator.Free;
    Other.Free;
    Tree.Free;
  end;
end;

const
  { RFC 3986 5.4: the examples of resolution against http://a/b/c/d;p?q
    (Saxon uses java.net.URI, which differs for ?y, "..." beyond the
    root and g..) }
  RfcExamples: array[0..41, 0..1] of string = (
    ('g:h', 'g:h'),
    ('g', 'http://a/b/c/g'),
    ('./g', 'http://a/b/c/g'),
    ('g/', 'http://a/b/c/g/'),
    ('/g', 'http://a/g'),
    ('//g', 'http://g'),
    ('?y', 'http://a/b/c/d;p?y'),
    ('g?y', 'http://a/b/c/g?y'),
    ('#s', 'http://a/b/c/d;p?q#s'),
    ('g#s', 'http://a/b/c/g#s'),
    ('g?y#s', 'http://a/b/c/g?y#s'),
    (';x', 'http://a/b/c/;x'),
    ('g;x', 'http://a/b/c/g;x'),
    ('g;x?y#s', 'http://a/b/c/g;x?y#s'),
    ('', 'http://a/b/c/d;p?q'),
    ('.', 'http://a/b/c/'),
    ('./', 'http://a/b/c/'),
    ('..', 'http://a/b/'),
    ('../', 'http://a/b/'),
    ('../g', 'http://a/b/g'),
    ('../..', 'http://a/'),
    ('../../', 'http://a/'),
    ('../../g', 'http://a/g'),
    ('../../../g', 'http://a/g'),
    ('../../../../g', 'http://a/g'),
    ('/./g', 'http://a/g'),
    ('/../g', 'http://a/g'),
    ('g.', 'http://a/b/c/g.'),
    ('.g', 'http://a/b/c/.g'),
    ('g..', 'http://a/b/c/g..'),
    ('..g', 'http://a/b/c/..g'),
    ('./../g', 'http://a/b/g'),
    ('./g/.', 'http://a/b/c/g/'),
    ('g/./h', 'http://a/b/c/g/h'),
    ('g/../h', 'http://a/b/c/h'),
    ('g;x=1/./y', 'http://a/b/c/g;x=1/y'),
    ('g;x=1/../y', 'http://a/b/c/y'),
    ('g?y/./x', 'http://a/b/c/g?y/./x'),
    ('g?y/../x', 'http://a/b/c/g?y/../x'),
    ('g#s/./x', 'http://a/b/c/g#s/./x'),
    ('g#s/../x', 'http://a/b/c/g#s/../x'),
    ('http:g', 'http:g'));

procedure TestResolveUri;
var
  Tree: TLandrixXmlXPathTree;
  Evaluator: TLandrixXmlXPathEvaluator;
  Expr: TLandrixXmlXPathExpression;
  I: Integer;
begin
  Tree := TLandrixXmlXPathTree.Create;
  Evaluator := TLandrixXmlXPathEvaluator.Create(Tree);
  Expr := nil;
  try
    Tree.LoadFromUtf8(U('<r/>'));
    for I := 0 to High(RfcExamples) do
    begin
      Expr.Free;
      Expr := nil;
      Expr := TLandrixXmlXPathExpression.Create(U('string(resolve-uri(''' + RfcExamples[I][0] +
        ''', ''http://a/b/c/d;p?q''))'), nil);
      CheckEqualsStr(RfcExamples[I][1], LandrixXmlUtf8ToString(Evaluator.EvaluateString(Expr, 0)),
        'resolve-uri ''' + RfcExamples[I][0] + '''');
    end;
    { no static base URI }
    Expr.Free;
    Expr := nil;
    Expr := TLandrixXmlXPathExpression.Create(U('string(empty(static-base-uri()))'), nil);
    CheckEqualsStr('true', LandrixXmlUtf8ToString(Evaluator.EvaluateString(Expr, 0)), 'static-base-uri()');
  finally
    Expr.Free;
    Evaluator.Free;
    Tree.Free;
  end;
end;

{ base-uri where the Saxon test data cannot show it (they load files):
  no BaseUri (Saxon gives the same for a document without a system ID,
  except where java.net.URI differs from RFC 3986: "?q", ".." beyond
  the root, file:///), and a BaseUri set by the caller. }
procedure TestBaseUri;
const
  Doc = '<r xml:base="rel/x"><a xml:base="b/c"><d xml:base="../e"/><f xml:base="/g"/><h xml:base="#k"/>' +
    '<i xml:base="?q"/></a><j xml:base="http://e.com/a/b/c/d"><k xml:base="?q=1"/><l xml:base="../../../../up"/>' +
    '</j><m xml:base="file:///C:/dir/"><n xml:base="sub/"/></m><o2 xml:base="//h.org"><o xml:base="p/x"/></o2>' +
    '<p2 xml:base="../../e"/><q2 xml:base="../e"/><s2 xml:base="./"/><u2 xml:base="..//e"/>' +
    '<v2 xml:base="../a:b"><w2 xml:base="#f"/></v2></r>';
  Cases: array[0..19] of array[0..1] of string = (
    ('base-uri(/)', ''),
    ('base-uri(/r)', 'rel/x'),
    ('base-uri(//a)', 'rel/b/c'),
    ('base-uri(//d)', 'rel/e'),
    ('base-uri(//f)', '/g'),
    ('base-uri(//h)', 'rel/b/c#k'),
    ('base-uri(//i)', 'rel/b/c?q'),
    ('base-uri(//a/@xml:base)', 'rel/b/c'),
    ('base-uri(//k)', 'http://e.com/a/b/c/d?q=1'),
    ('base-uri(//l)', 'http://e.com/up'),
    ('base-uri(//n)', 'file:///C:/dir/sub/'),
    ('count(base-uri(/))', '0'),
    ('base-uri(//o)', '//h.org/p/x'),
    ('base-uri(//p2)', '../e'),
    ('base-uri(//q2)', 'e'),
    ('base-uri(//s2)', 'rel/'),
    ('base-uri(//u2)', 'e'),
    ('base-uri(//v2)', './a:b'),
    ('base-uri(//w2)', './a:b#f'),
    ('count(document-uri(/))', '0'));
var
  Tree: TLandrixXmlXPathTree;
  Evaluator: TLandrixXmlXPathEvaluator;
  Expr: TLandrixXmlXPathExpression;
  I: Integer;
begin
  Tree := TLandrixXmlXPathTree.Create;
  Evaluator := nil;
  Expr := nil;
  try
    Tree.LoadFromUtf8(U(Doc));
    CheckEqualsStr('', LandrixXmlUtf8ToString(Tree.BaseUri), 'LoadFromUtf8: no base URI');
    Evaluator := TLandrixXmlXPathEvaluator.Create(Tree);
    for I := 0 to High(Cases) do
    begin
      Expr.Free;
      Expr := nil;
      Expr := TLandrixXmlXPathExpression.Create(U('string(' + Cases[I][0] + ')'), nil);
      CheckEqualsStr(Cases[I][1], LandrixXmlUtf8ToString(Evaluator.EvaluateString(Expr, 0)), Cases[I][0]);
    end;
    Evaluator.Free;
    Evaluator := nil;
    { the outermost relative value is normalised }
    Tree.LoadFromUtf8(U('<r xml:base="./a/../x"><c xml:base="#f"/></r>'));
    Evaluator := TLandrixXmlXPathEvaluator.Create(Tree);
    Expr.Free;
    Expr := nil;
    Expr := TLandrixXmlXPathExpression.Create(U('concat(base-uri(/r), '' '', base-uri(//c))'), nil);
    CheckEqualsStr('x x#f', LandrixXmlUtf8ToString(Evaluator.EvaluateString(Expr, 0)), 'outermost normalised');
    Evaluator.Free;
    Evaluator := nil;
    Tree.LoadFromUtf8(U(Doc));
    { a base URI set by the caller; relative values resolve against it }
    Tree.BaseUri := U('http://h.org/p/q.xml');
    Evaluator := TLandrixXmlXPathEvaluator.Create(Tree);
    Expr.Free;
    Expr := nil;
    Expr := TLandrixXmlXPathExpression.Create(U('concat(base-uri(/), '' '', base-uri(//d))'), nil);
    CheckEqualsStr('http://h.org/p/q.xml http://h.org/p/rel/e',
      LandrixXmlUtf8ToString(Evaluator.EvaluateString(Expr, 0)), 'BaseUri set');
    { it is the document URI too, and doc() finds the document by it }
    Expr.Free;
    Expr := nil;
    Expr := TLandrixXmlXPathExpression.Create(U('concat(document-uri(/), '' '', count(document-uri(/r)), '' '', ' +
      'doc(''http://h.org/p/q.xml'') is /, '' '', doc-available(''http://h.org/p/q.xml''), '' '', ' +
      'doc-available(''http://h.org/p/x.xml''), '' '', document(''http://h.org/p/q.xml'') is /)'), nil);
    CheckEqualsStr('http://h.org/p/q.xml 0 true true false true',
      LandrixXmlUtf8ToString(Evaluator.EvaluateString(Expr, 0)), 'document URI');
    Evaluator.Free;
    Evaluator := nil;
    Tree.LoadFromFile(DataFolder('baseuri') + 'd.xml');
    Check(Copy(Tree.BaseUri, 1, 6) = 'file:/', 'LoadFromFile: a file URI');
    Tree.LoadFromUtf8(U('<r/>'));
    CheckEqualsStr('', LandrixXmlUtf8ToString(Tree.BaseUri), 'a later load resets the base URI');
  finally
    Expr.Free;
    Evaluator.Free;
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

{ fn:lang in both profiles: XPath 2.0 folds case as Unicode's caseless
  match (the sharp s is ss), Saxon as Java's equalsIgnoreCase (dotless i
  equals dotted capital I). A document added later is available at once
  (no kept value of doc-available). }
procedure TestLangAndDocuments;
const
  Cases: array[0..7, 0..2] of string = (
    ('lang(''it'', /r/b)', 'xs:boolean false', 'xs:boolean true'),
    ('lang(codepoints-to-string(7838), /r)', 'xs:boolean true', 'xs:boolean true'),
    ('lang(''ss'', /r)', 'xs:boolean true', 'xs:boolean false'),
    ('lang(''SS-X'', /r)', 'xs:boolean true', 'xs:boolean false'),
    ('lang(codepoints-to-string(223), /r)', 'xs:boolean true', 'xs:boolean true'),
    ('lang(codepoints-to-string((305, 116)), /r/a)', 'xs:boolean false', 'xs:boolean true'),
    ('lang(''it'', /r/a)', 'xs:boolean false', 'xs:boolean true'),
    ('lang(''de'', /r/a)', 'xs:boolean false', 'xs:boolean false'));
var
  Tree, Late, Later: TLandrixXmlXPathTree;
  Evaluator: TLandrixXmlXPathEvaluator;
  Expr, Bound: TLandrixXmlXPathExpression;
  Context: TLandrixXmlXPathStaticContext;
  I: Integer;
begin
  Tree := TLandrixXmlXPathTree.Create;
  Late := TLandrixXmlXPathTree.Create;
  Later := TLandrixXmlXPathTree.Create;
  Evaluator := TLandrixXmlXPathEvaluator.Create(Tree);
  Context := TLandrixXmlXPathStaticContext.Create;
  Expr := nil;
  Bound := nil;
  try
    { the sharp s and the dotted capital I }
    Tree.LoadFromUtf8(U('<r xml:lang="&#223;-x"><a xml:lang="&#304;t"/><b xml:lang="&#305;t"/></r>'));
    for I := 0 to High(Cases) do
    begin
      CheckEqualsUtf8(U(Cases[I][1]), ProfileResult(U(Cases[I][0]), xppXPath20, Evaluator), 'XPath 2.0: ' + Cases[I][0]);
      CheckEqualsUtf8(U(Cases[I][2]), ProfileResult(U(Cases[I][0]), xppSaxon, Evaluator), 'Saxon: ' + Cases[I][0]);
    end;
    Expr := TLandrixXmlXPathExpression.Create(U('doc-available(''late.xml'')'), nil);
    CheckEqualsStr('false', LandrixXmlUtf8ToString(Evaluator.EvaluateString(Expr, 0)), 'not added yet');
    Late.LoadFromUtf8(U('<late/>'));
    Evaluator.AddDocument(U('late.xml'), Late);
    CheckEqualsStr('true', LandrixXmlUtf8ToString(Evaluator.EvaluateString(Expr, 0)), 'added afterwards');
    { a lazy variable read before is evaluated again }
    Evaluator.SetGlobalCount(1);
    Bound := TLandrixXmlXPathExpression.Create(U('doc-available(''later.xml'')'), nil);
    Evaluator.BindLazy(0, Bound, 0);
    Context.DeclareVariable(U('v'));
    Expr.Free;
    Expr := nil;
    Expr := TLandrixXmlXPathExpression.Create(U('$v'), Context);
    CheckEqualsStr('false', LandrixXmlUtf8ToString(Evaluator.EvaluateString(Expr, 0)), 'variable: not added yet');
    Later.LoadFromUtf8(U('<later/>'));
    Evaluator.AddDocument(U('later.xml'), Later);
    CheckEqualsStr('true', LandrixXmlUtf8ToString(Evaluator.EvaluateString(Expr, 0)), 'variable: added afterwards');
    Expr.Free;
    Expr := nil;
    Expr := TLandrixXmlXPathExpression.Create(U('document-uri(doc(''late.xml''))'), nil);
    CheckEqualsStr('late.xml', LandrixXmlUtf8ToString(Evaluator.EvaluateString(Expr, 0)), 'its URI');
  finally
    Expr.Free;
    Bound.Free;
    Context.Free;
    Evaluator.Free;
    Later.Free;
    Late.Free;
    Tree.Free;
  end;
end;

{ The implicit time zone and the current dateTime: defaults, changes
  after a first evaluation (kept values and lazy variables are dropped),
  a set and a cleared clock; years before 1 in XPath 2.0. }
procedure TestDateContext;
var
  Tree: TLandrixXmlXPathTree;
  Context: TLandrixXmlXPathStaticContext;
  Evaluator: TLandrixXmlXPathEvaluator;
  Lazy, Expr: TLandrixXmlXPathExpression;
  Slot: Integer;
  D: TLandrixXmlXsdDateTime;
  Raised: Boolean;

  function Eval(const Text: string): string;
  var
    E: TLandrixXmlXPathExpression;
  begin
    E := TLandrixXmlXPathExpression.Create(U(Text), Context);
    try
      Result := LandrixXmlUtf8ToString(Evaluator.EvaluateString(E, 0));
    finally
      E.Free;
    end;
  end;

  { the XPath error code of Text, '' if there is none }
  function ErrorOf(const Text: string): string;
  begin
    Result := '';
    try
      Eval(Text);
    except
      on E: ELandrixXmlXPathError do
        Result := E.XPathCode;
    end;
  end;

begin
  Tree := TLandrixXmlXPathTree.Create;
  Context := TLandrixXmlXPathStaticContext.Create;
  Context.Profile := xppXPath20;
  Evaluator := TLandrixXmlXPathEvaluator.Create(Tree);
  Lazy := nil;
  Expr := nil;
  try
    Tree.LoadFromUtf8(U('<r/>'));
    Slot := Context.DeclareVariable(U('zone'));
    Lazy := TLandrixXmlXPathExpression.Create(U('implicit-timezone()'), Context);
    Evaluator.SetGlobalCount(1);
    Evaluator.SetFrameSize(Context.VariableCount);
    Evaluator.BindLazy(Slot, Lazy, 0);
    CheckEquals(0, Evaluator.ImplicitTimeZone, 'default UTC');
    CheckEqualsStr('PT0S', Eval('implicit-timezone()'), 'implicit-timezone()');
    CheckEqualsStr('PT0S', Eval('$zone'), 'a lazy variable');
    CheckEqualsStr('true', Eval('xs:dateTime(''2024-01-01T10:00:00'') eq xs:dateTime(''2024-01-01T10:00:00Z'')'),
      'no time zone is UTC');
    Evaluator.ImplicitTimeZone := 60;
    CheckEqualsStr('PT1H', Eval('implicit-timezone()'), 'the kept value is dropped');
    CheckEqualsStr('PT1H', Eval('$zone'), 'the lazy variable is evaluated again');
    CheckEqualsStr('true', Eval('xs:dateTime(''2024-01-01T10:00:00'') eq xs:dateTime(''2024-01-01T09:00:00Z'')'),
      'compared in +01:00');
    CheckEqualsStr('PT1H', Eval('xs:dateTime(''2024-01-01T10:00:00'') - xs:dateTime(''2024-01-01T08:00:00Z'')'),
      'subtracted in +01:00');
    CheckEqualsStr('2024-01-01T10:00:00+01:00', Eval('adjust-dateTime-to-timezone(xs:dateTime(''2024-01-01T10:00:00''))'),
      'adjusted to the implicit time zone');
    Raised := False;
    try
      Evaluator.ImplicitTimeZone := 841;
    except
      on ELandrixXmlError do
        Raised := True;
    end;
    Check(Raised, 'more than 14 hours');
    D.Year := 2024;
    D.Month := 2;
    D.Day := 30;
    D.Hour := 0;
    D.Minute := 0;
    D.Second := LandrixXmlDecimalZero;
    D.HasTimeZone := False;
    D.TimeZone := 0;
    Raised := False;
    try
      Evaluator.CurrentDateTime := D;
    except
      on ELandrixXmlError do
        Raised := True;
    end;
    Check(Raised, 'February 30 is no clock');
    CheckEquals(60, Evaluator.ImplicitTimeZone, 'unchanged after the error');
    { a set clock, with its time zone adjusted to the implicit one }
    D.Year := 2024;
    D.Month := 12;
    D.Day := 31;
    D.Hour := 23;
    D.Minute := 30;
    D.Second := LandrixXmlParseDecimal(U('15.5'));
    D.HasTimeZone := True;
    D.TimeZone := 0;
    Evaluator.CurrentDateTime := D;
    CheckEqualsStr('2025-01-01T00:30:15.5+01:00', Eval('current-dateTime()'), 'the set clock');
    CheckEqualsStr('2025-01-01+01:00', Eval('current-date()'), 'its date');
    CheckEqualsStr('00:30:15.5+01:00', Eval('current-time()'), 'its time');
    CheckEqualsStr('true', Eval('current-dateTime() eq current-dateTime()'), 'stable');
    D := Evaluator.CurrentDateTime;
    CheckEquals(2025, D.Year, 'read back in the implicit time zone');
    Evaluator.ImplicitTimeZone := -300;
    CheckEqualsStr('2024-12-31T18:30:15.5-05:00', Eval('current-dateTime()'), 'the same instant in -05:00');
    D.HasTimeZone := False;
    D.Year := 2030;
    Evaluator.CurrentDateTime := D;
    CheckEqualsStr('2030-01-01T00:30:15.5-05:00', Eval('current-dateTime()'), 'a clock without time zone gets it');
    Evaluator.ClearCurrentDateTime;
    Check(StrToInt(Eval('year-from-date(current-date())')) >= 2026, 'the system clock after clearing');
    CheckEqualsStr('-PT5H', Eval('timezone-from-dateTime(current-dateTime())'), 'with the implicit time zone');
    { XML Schema 1.0 years: no year 0 }
    CheckEqualsStr('-0001-12-31', Eval('xs:date(''0001-01-01'') - xs:dayTimeDuration(''P1D'')'), 'before year 1');
    CheckEqualsStr('0001-01-01', Eval('xs:date(''-0001-12-31'') + xs:dayTimeDuration(''P1D'')'), 'after year -1');
    CheckEqualsStr('0001-01-01', Eval('xs:date(''-0001-01-01'') + xs:yearMonthDuration(''P1Y'')'), 'a year after -1');
    CheckEqualsStr('-0001-03-01', Eval('xs:date(''-0001-02-28'') + xs:dayTimeDuration(''P1D'')'),
      '-0001 is no leap year (the rule on the signed year, as the parser)');
    CheckEqualsStr('-0004-02-29', Eval('xs:date(''-0004-02-28'') + xs:dayTimeDuration(''P1D'')'), '-0004 is one');
    CheckEqualsStr('-0004-02-29', Eval('xs:date(''-0004-02-29'') + xs:yearMonthDuration(''P0M'')'), 'and stays');
    CheckEqualsStr('P1D', Eval('xs:date(''-0004-03-01'') - xs:date(''-0004-02-29'')'), 'a day apart');
    CheckEqualsStr('P365D', Eval('xs:date(''0001-01-01'') - xs:date(''-0001-01-01'')'), 'the year -1 has 365 days');
    CheckEqualsStr('-0002-12-31', Eval('xs:date(''-0001-01-01'') - xs:dayTimeDuration(''P1D'')'), 'the year before -1');
    CheckEqualsStr('true', Eval('xs:dateTime(''-0004-02-28T24:00:00'') eq ' +
      'xs:dateTime(''-0004-02-28T23:59:59'') + xs:dayTimeDuration(''PT1S'')'), '24:00:00 agrees with the arithmetic');
    CheckEqualsStr('0001-01-01T00:00:00', Eval('xs:dateTime(''-0001-12-31T24:00:00'')'), 'no year 0 after 24:00:00');
    CheckEqualsStr('15:30:07', Eval('xs:time(''00:00:00'') + xs:dayTimeDuration(''PT1S'') * 9223372036854775807'),
      'a huge duration on a time');
    CheckEqualsStr('FODT0001', ErrorOf('xs:date(''1970-01-01'') - xs:dayTimeDuration(''PT1S'') * 9223372036854775807'),
      'far before the first year');
    CheckEqualsStr('FODT0001', ErrorOf('xs:date(''-2147483648-06-01'')'), 'the year -2^31');
    CheckEqualsStr('FODT0001', ErrorOf('xs:dateTime(''2147483647-12-31T24:00:00'')'), 'the last year ends');
    CheckEqualsStr('FORG0001', ErrorOf('xs:date(''02147483648-01-01'')'), 'a leading zero');
    CheckEqualsStr('FODT0001', ErrorOf('xs:date(''-99999999996-02-29'')'), 'a large leap year');
    CheckEqualsStr('-0044', Eval('substring(string(xs:date(''-0044-03-15'')), 1, 5)'), 'negative years keep their text');
    Expr := TLandrixXmlXPathExpression.Create(U('xs:date(''2147483647-12-31'') + xs:dayTimeDuration(''P1D'')'), Context);
    Raised := False;
    try
      Evaluator.EvaluateString(Expr, 0);
    except
      on E: ELandrixXmlXPathError do
        Raised := E.XPathCode = 'FODT0001';
    end;
    Check(Raised, 'year overflow FODT0001');
  finally
    Expr.Free;
    Lazy.Free;
    Evaluator.Free;
    Context.Free;
    Tree.Free;
  end;
end;

{ The limits of durations where Saxon's own results are wrong (its
  canonical form overflows), in both profiles. }
procedure TestDurationLimits;
var
  Tree: TLandrixXmlXPathTree;
  Evaluator: TLandrixXmlXPathEvaluator;
  Profile: TLandrixXmlXPathProfile;

  procedure Expect(const Expr, Want: string);
  begin
    Check(ProfileResult(U(Expr), Profile, Evaluator) = U(Want), Expr + ': ' +
      LandrixXmlUtf8ToString(ProfileResult(U(Expr), Profile, Evaluator)));
  end;

begin
  Tree := TLandrixXmlXPathTree.Create;
  Evaluator := TLandrixXmlXPathEvaluator.Create(Tree);
  try
    Tree.LoadFromUtf8(U('<r/>'));
    for Profile := Low(TLandrixXmlXPathProfile) to High(TLandrixXmlXPathProfile) do
    begin
      Expect('xs:dayTimeDuration(''PT1S'') * -9223372036854775807',
        'xs:dayTimeDuration -P106751991167300DT15H30M7S');
      Expect('xs:dayTimeDuration(''PT1S'') * -9223372036854775808', 'error FODT0002');
      Expect('xs:dayTimeDuration(''-PT1S'') * 9223372036854775808', 'error FODT0002');
      Expect('days-from-duration(xs:dayTimeDuration(''PT1S'') * 9223372036854775807)', 'xs:integer 106751991167300');
      Expect('xs:dayTimeDuration(''P2147483647D'') + xs:dayTimeDuration(''P2147483647D'')',
        'xs:dayTimeDuration P4294967294D');
      Expect('xs:yearMonthDuration(''P2147483647M'') + xs:yearMonthDuration(''P1M'')', 'error FODT0002');
      Expect('xs:yearMonthDuration(''-P2147483647M'') - xs:yearMonthDuration(''P1M'')', 'error FODT0002');
      Expect('xs:date(''2000-01-01'') + xs:dayTimeDuration(''P1D'')', 'xs:date 2000-01-02');
    end;
  finally
    Evaluator.Free;
    Tree.Free;
  end;
end;

{ round-half-to-even and round with a precision beyond Integer or far
  below the digits of a large value (Saxon crashes on these). }
procedure TestPrecisionLimits;
const
  { 10^100001 }
  Big = 'xs:integer(concat(''1'', string-join(for $i in 1 to 100001 return ''0'', '''')))';
  { 10^1000000, the largest exponent of a decimal }
  Huge = 'xs:integer(concat(''1'', string-join(for $i in 1 to 1000000 return ''0'', '''')))';
var
  Tree: TLandrixXmlXPathTree;
  Evaluator: TLandrixXmlXPathEvaluator;
  Profile: TLandrixXmlXPathProfile;

  procedure Expect(const Expr, Want: string);
  begin
    Check(ProfileResult(U(Expr), Profile, Evaluator) = U(Want), Expr + ': ' +
      LandrixXmlUtf8ToString(ProfileResult(U(Expr), Profile, Evaluator)));
  end;

begin
  Tree := TLandrixXmlXPathTree.Create;
  Evaluator := TLandrixXmlXPathEvaluator.Create(Tree);
  try
    Tree.LoadFromUtf8(U('<r/>'));
    for Profile := Low(TLandrixXmlXPathProfile) to High(TLandrixXmlXPathProfile) do
    begin
      Expect('round-half-to-even(' + Big + ', -100002) eq 0', 'xs:boolean true');
      Expect('round-half-to-even(' + Big + ', -2147483649) eq 0', 'xs:boolean true');
      Expect('round-half-to-even(' + Big + ', -100001) eq ' + Big, 'xs:boolean true');
      Expect('round-half-to-even(' + Huge + ', -2147483649) eq 0', 'xs:boolean true');
      Expect('round-half-to-even(' + Huge + ', -1000001) eq 0', 'xs:boolean true');
      Expect('round-half-to-even(' + Huge + ', -1000002) eq 0', 'xs:boolean true');
      Expect('round-half-to-even(0.4, -1) eq 0', 'xs:boolean true');
      Expect('round-half-to-even(65, -2)', 'xs:integer 100');
      Expect('round-half-to-even(-65, -3)', 'xs:integer 0');
      Expect('round-half-to-even(3.5, -99999999999999999999)', 'xs:decimal 0');
      Expect('round-half-to-even(-35, -9223372036854775808)', 'xs:integer 0');
      Expect('round-half-to-even(3.5E0, -4294967296)', 'xs:double 0');
      Expect('round-half-to-even(2.5, 9223372036854775808)', 'xs:decimal 2.5');
    end;
  finally
    Evaluator.Free;
    Tree.Free;
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
      Def.ResultType.AtomicType := xikDouble;
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
  RegisterTest('XPathEval.OracleCases', TestOracleCases);
  RegisterTest('XPathEval.DurationLimits', TestDurationLimits);
  RegisterTest('XPathEval.PrecisionLimits', TestPrecisionLimits);
  RegisterTest('XPathEval.DateContext', TestDateContext);
  RegisterTest('XPathEval.MixedProfiles', TestMixedProfiles);
  RegisterTest('XPathEval.Profiles', TestProfiles);
  RegisterTest('XPathEval.Variables', TestVariables);
  RegisterTest('XPathEval.SequenceTypeMatching', TestSequenceTypeMatching);
  RegisterTest('XPathEval.NoAliasing', TestNoAliasing);
  RegisterTest('XPathEval.KeptValues', TestKeptValues);
  RegisterTest('XPathEval.Patterns', TestPatterns);
  RegisterTest('XPathEval.Documents', TestDocuments);
  RegisterTest('XPathEval.DeepEqual', TestDeepEqual);
  RegisterTest('XPathEval.ResolveUri', TestResolveUri);
  RegisterTest('XPathEval.BaseUri', TestBaseUri);
  RegisterTest('XPathEval.LangAndDocuments', TestLangAndDocuments);
end;

end.
