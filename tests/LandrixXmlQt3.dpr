{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Helper of tools/run-qt3.py (the W3C XPath test suite QT3): evaluates the
  cases of a job file and writes their results; the driver checks the
  assertions. Usage: LandrixXmlQt3 <job-file> <result-file> [first-case]

  Job file (UTF-8, one item per line, "\xHH" for control characters and
  the backslash):
    case NAME
    source FILE        the context item is the document node of FILE
    var NAME FILE      $NAME is the document node of FILE
    doc URI FILE       document(URI) returns FILE
    ns PREFIX URI
    profile saxon      the Saxon profile (else XPath 2.0)
    param NAME EXPR    $NAME is the value of EXPR
    expr EXPR          the expression under test
    check EXPR         evaluated with $result bound to its value
    value EXPR         evaluated on its own (the expected value of assert-eq)
    run
  Result file: "case NAME", then per value (R the expression, C1.. the
  checks, V1.. the values) "X count N" and one line per item ("X TYPE
  VALUE", "X node KIND NAME VALUE"; NAME as in LocationPathUtf8 or -) or
  "X error CODE MESSAGE" (an XPath error) or "X exception CLASS MESSAGE"
  (any other exception); "done" after the case. Every line is written at
  once, so a crash leaves the cases before it complete. Only the context
  item, variables and params are set; everything else is the default
  static and dynamic context. }

program LandrixXmlQt3;

{$I LandrixXml.inc}

{$IFDEF MSWINDOWS}
  {$APPTYPE CONSOLE}
{$ENDIF}

uses
  SysUtils,
  Classes,
  LandrixXmlBase,
  LandrixXmlXPathTree,
  LandrixXmlXPath,
  LandrixXmlXPathEval;

const
  ResultName = 'result';
  { bound to a value while it is written; not a name QT3 uses }
  ItemsName = 'landrixxml-qt3-items';

var
  Output: TFileStream;

procedure Put(const Line: TLandrixXmlUtf8);
var
  S: TLandrixXmlUtf8;
begin
  S := Line + #10;
  Output.WriteBuffer(PAnsiChar(S)^, Length(S));
end;

function U(const S: string): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(S);
end;

{ \xHH for control characters and the backslash, and for spaces when the
  text is not the last field of a line }
function Esc(const S: TLandrixXmlUtf8; Spaces: Boolean): TLandrixXmlUtf8;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    if (Ord(S[I]) < 32) or (S[I] = '\') or (Spaces and (S[I] = ' ')) then
      Result := Result + U('\x' + IntToHex(Ord(S[I]), 2))
    else
      Result := Result + Copy(S, I, 1);
end;

function HexDigit(C: AnsiChar): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
  else
    Result := -1;
  end;
end;

function Unesc(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I, N: Integer;
begin
  Result := '';
  SetLength(Result, Length(S));
  N := 0;
  I := 1;
  while I <= Length(S) do
  begin
    Inc(N);
    if (S[I] = '\') and (I + 3 <= Length(S)) and (S[I + 1] = 'x') and (HexDigit(S[I + 2]) >= 0) and
      (HexDigit(S[I + 3]) >= 0) then
    begin
      Result[N] := AnsiChar(16 * HexDigit(S[I + 2]) + HexDigit(S[I + 3]));
      Inc(I, 4);
    end
    else
    begin
      Result[N] := S[I];
      Inc(I);
    end;
  end;
  SetLength(Result, N);
end;

function FileLines(const FileName: string): TLandrixXmlUtf8Array;
var
  F: TFileStream;
  Data: TLandrixXmlUtf8;
  I, Start, N: Integer;
begin
  Result := nil;
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    Data := '';
    SetLength(Data, Integer(F.Size));
    if Length(Data) > 0 then
      F.ReadBuffer(PAnsiChar(Data)^, Length(Data));
  finally
    F.Free;
  end;
  N := 0;
  Start := 1;
  for I := 1 to Length(Data) + 1 do
    if (I > Length(Data)) or (Data[I] = #10) then
    begin
      if I > Start then
      begin
        if N = Length(Result) then
          SetLength(Result, 2 * N + 64);
        Result[N] := Copy(Data, Start, I - Start);
        Inc(N);
      end;
      Start := I + 1;
    end;
  SetLength(Result, N);
end;

{ the text before the first space (Head) and after it (the result) }
function Split(const S: TLandrixXmlUtf8; out Head: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  P: Integer;
begin
  P := 1;
  while (P <= Length(S)) and (S[P] <> ' ') do
    Inc(P);
  Head := Copy(S, 1, P - 1);
  Result := Copy(S, P + 1, MaxInt);
end;

const
  KindNames: array[TLandrixXmlXPathItemKind] of string = ('node', 'xs:untypedAtomic', 'xs:string', 'xs:anyURI',
    'xs:boolean', 'xs:integer', 'xs:decimal', 'xs:double', 'xs:date', 'xs:dateTime', 'xs:time', 'xs:float', 'xs:anyAtomicType', 'none',
    'xs:nonPositiveInteger', 'xs:negativeInteger', 'xs:long', 'xs:int', 'xs:short', 'xs:byte',
    'xs:nonNegativeInteger', 'xs:unsignedLong', 'xs:unsignedInt', 'xs:unsignedShort', 'xs:unsignedByte',
    'xs:positiveInteger',
    'xs:normalizedString', 'xs:token', 'xs:language', 'xs:NMTOKEN', 'xs:Name', 'xs:NCName', 'xs:ID',
    'xs:IDREF', 'xs:ENTITY', 'xs:duration', 'xs:yearMonthDuration', 'xs:dayTimeDuration');
  NodeKindNames: array[TLandrixXmlXPathNodeKind] of string = ('document-node', 'element', 'attribute', 'text',
    'comment', 'processing-instruction');

type
  { One case of the job file. }
  TCase = class
  public
    Name: TLandrixXmlUtf8;
    Source: string;
    VarNames: TLandrixXmlUtf8Array;
    VarFiles: array of string;
    DocUris: TLandrixXmlUtf8Array;
    DocFiles: array of string;
    NsPrefixes: TLandrixXmlUtf8Array;
    NsUris: TLandrixXmlUtf8Array;
    ParamNames: TLandrixXmlUtf8Array;
    ParamExprs: TLandrixXmlUtf8Array;
    Expr: TLandrixXmlUtf8;
    Checks: TLandrixXmlUtf8Array;
    Values: TLandrixXmlUtf8Array;
    Saxon: Boolean;
  end;

  { The trees and the evaluator of a case. }
  TRun = class
  public
    Main: TLandrixXmlXPathTree;
    Trees: TList;
    { the URI document() finds each tree by }
    TreeUris: TLandrixXmlUtf8Array;
    Bases: TLandrixXmlXPathIntArray;
    Context: TLandrixXmlXPathStaticContext;
    Evaluator: TLandrixXmlXPathEvaluator;
    Expressions: TList;
    ItemsSlot: Integer;
    ItemStrings: TLandrixXmlXPathExpression;
    constructor Create;
    destructor Destroy; override;
    function AddTree(const FileName: string; const Uri: TLandrixXmlUtf8): Integer;
    function Compile(const Text: TLandrixXmlUtf8): TLandrixXmlXPathExpression;
    procedure PutValue(const Tag: TLandrixXmlUtf8; const Value: TLandrixXmlXPathSequence);
  end;

procedure Add(var A: TLandrixXmlUtf8Array; const S: TLandrixXmlUtf8);
begin
  SetLength(A, Length(A) + 1);
  A[High(A)] := S;
end;

constructor TRun.Create;
begin
  inherited Create;
  Main := TLandrixXmlXPathTree.Create;
  Trees := TList.Create;
  Context := TLandrixXmlXPathStaticContext.Create;
  Expressions := TList.Create;
end;

destructor TRun.Destroy;
var
  I: Integer;
begin
  Evaluator.Free;
  for I := 0 to Integer(Expressions.Count) - 1 do
    TObject(Expressions[I]).Free;
  Expressions.Free;
  Context.Free;
  for I := 0 to Integer(Trees.Count) - 1 do
    TObject(Trees[I]).Free;
  Trees.Free;
  Main.Free;
  inherited Destroy;
end;

{ a further document (TLandrixXmlXPathEvaluator.AddDocument numbers its
  nodes after those of the trees before it): its document node }
function TRun.AddTree(const FileName: string; const Uri: TLandrixXmlUtf8): Integer;
var
  T: TLandrixXmlXPathTree;
  I: Integer;
begin
  T := TLandrixXmlXPathTree.Create;
  try
    T.LoadFromFile(FileName);
  except
    T.Free;
    raise;
  end;
  Trees.Add(T);
  Add(TreeUris, Uri);
  Result := Main.Count;
  for I := 0 to Integer(Trees.Count) - 2 do
    Inc(Result, TLandrixXmlXPathTree(Trees[I]).Count);
  SetLength(Bases, Integer(Trees.Count));
  Bases[Integer(Trees.Count) - 1] := Result;
end;

function TRun.Compile(const Text: TLandrixXmlUtf8): TLandrixXmlXPathExpression;
begin
  Result := TLandrixXmlXPathExpression.Create(Text, Context);
  Expressions.Add(Result);
end;

procedure TRun.PutValue(const Tag: TLandrixXmlUtf8; const Value: TLandrixXmlXPathSequence);
var
  Strings: TLandrixXmlXPathResult;
  I, K, Node: Integer;
  T: TLandrixXmlXPathTree;
  Name: TLandrixXmlUtf8;
begin
  Evaluator.BindValue(ItemsSlot, Value);
  Strings := Evaluator.Evaluate(ItemStrings, -1);
  try
    Put(Tag + U(' count ' + IntToStr(Value.Count)));
    for I := 0 to Value.Count - 1 do
      if Value.Items[I].Kind = xikNode then
      begin
        Node := Value.Items[I].Node;
        T := Main;
        for K := Integer(Trees.Count) - 1 downto 0 do
          if Node >= Bases[K] then
          begin
            T := TLandrixXmlXPathTree(Trees[K]);
            Dec(Node, Bases[K]);
            Break;
          end;
        if T.Kind[Node] in [xnkElement, xnkAttribute, xnkProcessingInstruction] then
          Name := U('Q{') + T.NamespaceUriUtf8(Node) + U('}') + T.LocalNameUtf8(Node)
        else
          Name := '-';
        Put(Tag + U(' node ' + NodeKindNames[T.Kind[Node]] + ' ') + Esc(Name, True) + ' ' +
          Esc(Strings.StringValueUtf8(I), False));
      end
      else
        Put(Tag + U(' ' + KindNames[Value.Items[I].Kind] + ' ') + Esc(Strings.StringValueUtf8(I), False));
  finally
    Strings.Free;
  end;
end;

{ an XPath error, or another exception (a defect, never an expected error) }
procedure PutError(const Tag: TLandrixXmlUtf8; E: Exception);
begin
  if E is ELandrixXmlXPathError then
    Put(Tag + U(' error ' + ELandrixXmlXPathError(E).XPathCode + ' ') + Esc(U(E.Message), False))
  else
    Put(Tag + U(' exception ' + E.ClassName + ' ') + Esc(U(E.Message), False));
end;

procedure RunCase(C: TCase);
var
  R: TRun;
  I, ContextNode, ResultSlot: Integer;
  Slots: array of Integer;
  Expr: TLandrixXmlXPathExpression;
  Value: TLandrixXmlXPathSequence;
  Ok: Boolean;
begin
  Slots := nil;
  ContextNode := -1;
  ResultSlot := -1;
  Put(U('case ') + Esc(C.Name, True));
  R := TRun.Create;
  try
    Ok := False;
    try
      if C.Source <> '' then
      begin
        R.Main.LoadFromFile(C.Source);
        ContextNode := 0;
      end;
      SetLength(Slots, Length(C.VarNames));
      for I := 0 to Integer(Length(C.VarNames)) - 1 do
        Slots[I] := R.AddTree(C.VarFiles[I], U('landrixxml-qt3-var:') + C.VarNames[I]);
      { a document only document() reads may be malformed: the error belongs
        to the call (FODC0002), so it is left out }
      for I := 0 to Integer(Length(C.DocUris)) - 1 do
        try
          R.AddTree(C.DocFiles[I], C.DocUris[I]);
        except
          on ELandrixXmlError do
            ;
        end;
      if C.Saxon then
        R.Context.Profile := xppSaxon;
      for I := 0 to Integer(Length(C.NsPrefixes)) - 1 do
        R.Context.AddNamespace(C.NsPrefixes[I], C.NsUris[I]);
      for I := 0 to Integer(Length(C.VarNames)) - 1 do
        R.Context.DeclareVariable(C.VarNames[I]);
      for I := 0 to Integer(Length(C.ParamNames)) - 1 do
        R.Context.DeclareVariable(C.ParamNames[I]);
      ResultSlot := R.Context.DeclareVariable(ResultName);
      R.ItemsSlot := R.Context.DeclareVariable(ItemsName);
      R.ItemStrings := R.Compile(U('for $i in $' + ItemsName + ' return string($i)'));
      R.Evaluator := TLandrixXmlXPathEvaluator.Create(R.Main);
      for I := 0 to Integer(R.Trees.Count) - 1 do
        R.Evaluator.AddDocument(R.TreeUris[I], TLandrixXmlXPathTree(R.Trees[I]));
      R.Evaluator.SetGlobalCount(R.Context.VariableCount);
      for I := 0 to Integer(Length(C.VarNames)) - 1 do
        R.Evaluator.BindValue(R.Context.DeclareVariable(C.VarNames[I]), LandrixXmlXPathNodeItem(Slots[I]));
      for I := 0 to Integer(Length(C.ParamNames)) - 1 do
        R.Evaluator.BindValue(R.Context.DeclareVariable(C.ParamNames[I]),
          R.Evaluator.EvaluateSequence(R.Compile(C.ParamExprs[I]), -1));
      Ok := True;
    except
      on E: Exception do
        Put(U('setup error ') + Esc(U(E.ClassName + ': ' + E.Message), False));
    end;
    if Ok then
    begin
      Ok := False;
      try
        Expr := R.Compile(C.Expr);
        Value := R.Evaluator.EvaluateSequence(Expr, ContextNode);
        R.PutValue('R', Value);
        R.Evaluator.BindValue(ResultSlot, Value);
        Ok := True;
      except
        on E: Exception do
          PutError('R', E);
      end;
      if Ok then
        for I := 0 to Integer(Length(C.Checks)) - 1 do
          try
            R.PutValue(U('C' + IntToStr(I + 1)), R.Evaluator.EvaluateSequence(R.Compile(C.Checks[I]), -1));
          except
            on E: Exception do
              PutError(U('C' + IntToStr(I + 1)), E);
          end;
      for I := 0 to Integer(Length(C.Values)) - 1 do
        try
          R.PutValue(U('V' + IntToStr(I + 1)), R.Evaluator.EvaluateSequence(R.Compile(C.Values[I]), -1));
        except
          on E: Exception do
            PutError(U('V' + IntToStr(I + 1)), E);
        end;
    end;
  finally
    R.Free;
  end;
  Put('done');
end;

var
  Lines: TLandrixXmlUtf8Array;
  C: TCase;
  I, Index, First: Integer;
  Head, Rest, Name: TLandrixXmlUtf8;

begin
  Lines := nil;
  if (ParamCount < 2) or (ParamCount > 3) then
  begin
    WriteLn('Usage: LandrixXmlQt3 <job-file> <result-file> [first-case]');
    ExitCode := 2;
    Exit;
  end;
  First := 0;
  if ParamCount = 3 then
    First := StrToInt(ParamStr(3));
  Lines := FileLines(ParamStr(1));
  Output := TFileStream.Create(ParamStr(2), fmCreate);
  C := nil;
  Index := -1;
  try
    for I := 0 to Integer(Length(Lines)) - 1 do
    begin
      Rest := Split(Lines[I], Head);
      if Head = 'case' then
      begin
        C.Free;
        C := TCase.Create;
        C.Name := Unesc(Rest);
        Inc(Index);
      end
      else if C = nil then
        Continue
      else if Head = 'source' then
        C.Source := LandrixXmlUtf8ToString(Unesc(Rest))
      else if Head = 'var' then
      begin
        Rest := Split(Rest, Name);
        Add(C.VarNames, Unesc(Name));
        SetLength(C.VarFiles, Length(C.VarFiles) + 1);
        C.VarFiles[High(C.VarFiles)] := LandrixXmlUtf8ToString(Unesc(Rest));
      end
      else if Head = 'doc' then
      begin
        Rest := Split(Rest, Name);
        Add(C.DocUris, Unesc(Name));
        SetLength(C.DocFiles, Length(C.DocFiles) + 1);
        C.DocFiles[High(C.DocFiles)] := LandrixXmlUtf8ToString(Unesc(Rest));
      end
      else if Head = 'ns' then
      begin
        Rest := Split(Rest, Name);
        Add(C.NsPrefixes, Unesc(Name));
        Add(C.NsUris, Unesc(Rest));
      end
      else if Head = 'param' then
      begin
        Rest := Split(Rest, Name);
        Add(C.ParamNames, Unesc(Name));
        Add(C.ParamExprs, Unesc(Rest));
      end
      else if Head = 'profile' then
        C.Saxon := Rest = 'saxon'
      else if Head = 'expr' then
        C.Expr := Unesc(Rest)
      else if Head = 'check' then
        Add(C.Checks, Unesc(Rest))
      else if Head = 'value' then
        Add(C.Values, Unesc(Rest))
      else if Head = 'run' then
      begin
        if Index >= First then
          RunCase(C);
        C.Free;
        C := nil;
      end;
    end;
  finally
    C.Free;
    Output.Free;
  end;
end.
