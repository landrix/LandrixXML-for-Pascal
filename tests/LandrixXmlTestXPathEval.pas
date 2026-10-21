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

procedure Register;
begin
  RegisterTest('XPathEval.SaxonCases', TestSaxonCases);
  RegisterTest('XPathEval.Variables', TestVariables);
  RegisterTest('XPathEval.NoAliasing', TestNoAliasing);
end;

end.
