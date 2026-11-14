{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Helper of tools/run-xslt-tests.py (the W3C XSLT test suite): runs one
  test case of a job file and writes what the driver needs to check its
  assertions. Usage: LandrixXmlXsltSuite <job-file> <result-file>

  Job file (UTF-8, one item per line, "\xHH" for control characters, the
  backslash and, in all fields but the last of a line, spaces):
    stylesheet FILE
    source FILE        the initial context is the document node of FILE
    template CLARK     the initial template
    mode CLARK         the initial mode
    ns PREFIX URI      for the param and check expressions
    param CLARK EXPR   the stylesheet parameter is the value of EXPR
    serialize FILE     the principal result as the stylesheet serializes it
    xml FILE           the principal result as XML (no indentation, no XML
                       declaration, whatever the stylesheet says)
    check EXPR         evaluated on the principal result (a document node:
                       the context item and $result)
  Result file: "serialized" (the file was written) or "error CODE
  MESSAGE" (an XPath or XSLT error), "unsupported MESSAGE" (xecUnsupported)
  or "exception CLASS MESSAGE"; with checks or xml, "tree" or the error of
  that run, with xml then "xml" (the file was written) or its error, with
  checks "string VALUE" (the string value of the result) and per check
  "check N true", "check N false" or "check N error CODE MESSAGE". }

program LandrixXmlXsltSuite;

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
  LandrixXmlXPathEval,
  LandrixXmlXslt,
  LandrixXmlXsltOutput;

const
  ResultName = 'result';

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

{ \xHH for control characters and the backslash }
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

procedure Add(var A: TLandrixXmlUtf8Array; const S: TLandrixXmlUtf8);
begin
  SetLength(A, Length(A) + 1);
  A[High(A)] := S;
end;

{ the line of an exception: error, unsupported or exception }
function ErrorLine(E: Exception): TLandrixXmlUtf8;
begin
  if (E is ELandrixXmlError) and (ELandrixXmlError(E).Code = xecUnsupported) then
    Result := U('unsupported ') + Esc(U(E.Message))
  else if E is ELandrixXmlXPathError then
    Result := U('error ' + ELandrixXmlXPathError(E).XPathCode + ' ') + Esc(U(E.Message))
  else
    Result := U('exception ' + E.ClassName + ' ') + Esc(U(E.Message));
end;

var
  Lines, NsPrefixes, NsUris, ParamNames, ParamExprs, Checks: TLandrixXmlUtf8Array;
  StylesheetFile, SourceFile, SerializeFile, XmlFile: string;
  Props: TXsltOutputProperties;
  Template, Mode, Head, Rest, Name: TLandrixXmlUtf8;
  Sheet: TLandrixXmlXsltStylesheet;
  Transformer: TLandrixXmlXsltTransformer;
  Source, Target: TLandrixXmlXPathTree;
  Stream: TFileStream;
  Context: TLandrixXmlXPathStaticContext;
  Evaluator: TLandrixXmlXPathEvaluator;
  Expressions: TList;
  Expr: TLandrixXmlXPathExpression;
  Value: TLandrixXmlXPathSequence;
  I, Slot: Integer;
  Ok: Boolean;

begin
  if ParamCount <> 2 then
  begin
    WriteLn('Usage: LandrixXmlXsltSuite <job-file> <result-file>');
    Halt(2);
  end;
  Lines := FileLines(ParamStr(1));
  NsPrefixes := nil;
  NsUris := nil;
  ParamNames := nil;
  ParamExprs := nil;
  Checks := nil;
  StylesheetFile := '';
  SourceFile := '';
  SerializeFile := '';
  XmlFile := '';
  Template := '';
  Mode := '';
  for I := 0 to Integer(Length(Lines)) - 1 do
  begin
    Rest := Split(Lines[I], Head);
    if Head = 'stylesheet' then
      StylesheetFile := LandrixXmlUtf8ToString(Unesc(Rest))
    else if Head = 'source' then
      SourceFile := LandrixXmlUtf8ToString(Unesc(Rest))
    else if Head = 'template' then
      Template := Unesc(Rest)
    else if Head = 'mode' then
      Mode := Unesc(Rest)
    else if Head = 'ns' then
    begin
      Rest := Split(Rest, Name);
      Add(NsPrefixes, Unesc(Name));
      Add(NsUris, Unesc(Rest));
    end
    else if Head = 'param' then
    begin
      Rest := Split(Rest, Name);
      Add(ParamNames, Unesc(Name));
      Add(ParamExprs, Unesc(Rest));
    end
    else if Head = 'serialize' then
      SerializeFile := LandrixXmlUtf8ToString(Unesc(Rest))
    else if Head = 'xml' then
      XmlFile := LandrixXmlUtf8ToString(Unesc(Rest))
    else if Head = 'check' then
      Add(Checks, Unesc(Rest));
  end;
  Output := TFileStream.Create(ParamStr(2), fmCreate);
  Sheet := TLandrixXmlXsltStylesheet.Create;
  Transformer := nil;
  Source := nil;
  Target := nil;
  Context := nil;
  Evaluator := nil;
  Expressions := TList.Create;
  try
    Ok := False;
    try
      Sheet.LoadFromFile(StylesheetFile);
      if SourceFile <> '' then
      begin
        Source := TLandrixXmlXPathTree.Create;
        Source.LoadFromFile(SourceFile);
      end;
      Transformer := TLandrixXmlXsltTransformer.Create(Sheet);
      Transformer.InitialTemplate := Template;
      Transformer.InitialMode := Mode;
      for I := 0 to Integer(Length(ParamNames)) - 1 do
        Transformer.SetParameterXPath(ParamNames[I], ParamExprs[I]);
      Ok := True;
    except
      on E: Exception do
        Put(ErrorLine(E));
    end;
    if Ok and (SerializeFile <> '') then
    begin
      Stream := nil;
      try
        try
          Stream := TFileStream.Create(SerializeFile, fmCreate);
          Transformer.Transform(Source, Stream);
          Put(U('serialized'));
        finally
          Stream.Free;
        end;
      except
        on E: Exception do
        begin
          Put(ErrorLine(E));
          Ok := False;
        end;
      end;
    end;
    if Ok and ((Length(Checks) > 0) or (XmlFile <> '')) then
    begin
      Ok := False;
      try
        Target := TLandrixXmlXPathTree.Create;
        Transformer.TransformToTree(Source, Target);
        Put(U('tree'));
        Ok := True;
      except
        on E: Exception do
          Put(ErrorLine(E));
      end;
      if Ok and (XmlFile <> '') then
      begin
        Stream := nil;
        Props := TXsltOutputProperties.Create;
        try
          try
            Props.SetValue('method', 'xml');
            Props.SetValue('indent', 'no');
            Props.SetValue('omit-xml-declaration', 'yes');
            Stream := TFileStream.Create(XmlFile, fmCreate);
            XsltSerialize(Target, Props, Stream, True);
            Put(U('xml'));
          finally
            Stream.Free;
            Props.Free;
          end;
        except
          on E: Exception do
            Put(U('xml-') + ErrorLine(E));
        end;
      end;
      if Ok and (Length(Checks) > 0) then
      begin
        Context := TLandrixXmlXPathStaticContext.Create;
        Context.Profile := xppSaxon;
        for I := 0 to Integer(Length(NsPrefixes)) - 1 do
          Context.AddNamespace(NsPrefixes[I], NsUris[I]);
        Slot := Context.DeclareVariable(ResultName);
        Evaluator := TLandrixXmlXPathEvaluator.Create(Target);
        Evaluator.SetGlobalCount(Context.VariableCount);
        Evaluator.BindValue(Slot, LandrixXmlXPathNodeItem(0));
        try
          Expr := TLandrixXmlXPathExpression.Create(U('string(/)'), Context);
          Expressions.Add(Expr);
          Value := Evaluator.EvaluateSequence(Expr, 0);
          Put(U('string ') + Esc(Evaluator.ItemString(Value.Items[0])));
        except
          on E: Exception do
            Put(U('string-') + ErrorLine(E));
        end;
        for I := 0 to Integer(Length(Checks)) - 1 do
          try
            Expr := TLandrixXmlXPathExpression.Create(U('boolean((') + Checks[I] + U('))'), Context);
            Expressions.Add(Expr);
            Value := Evaluator.EvaluateSequence(Expr, 0);
            Put(U('check ' + IntToStr(I + 1) + ' ') + Evaluator.ItemString(Value.Items[0]));
          except
            on E: Exception do
              Put(U('check ' + IntToStr(I + 1) + ' ') + ErrorLine(E));
          end;
      end;
    end;
  finally
    for I := 0 to Integer(Expressions.Count) - 1 do
      TObject(Expressions[I]).Free;
    Expressions.Free;
    Evaluator.Free;
    Context.Free;
    Target.Free;
    Transformer.Free;
    Source.Free;
    Sheet.Free;
    Output.Free;
  end;
end.
