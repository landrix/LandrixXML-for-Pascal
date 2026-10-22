{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Tests for the Schematron validator: the rule sets of
  tests/data/schematron/rules on the documents of ubl/ and cii/, compared
  with the SVRL of the KoSIT validator's XSLT under Saxon
  (tools/gen-schematron-testdata.py): the fired rules in order and every
  failed assert with id, flag, location and message; a document Saxon
  stops on must give a dynamic error. Plus small rule files for matching,
  results and load errors. }

unit LandrixXmlTestSchematron;

{$I LandrixXml.inc}

interface

procedure Register;

implementation

uses
  SysUtils,
  Classes,
  LandrixXmlBase,
  LandrixXmlDom,
  LandrixXmlXPathTree,
  LandrixXmlXPath,
  LandrixXmlSchematron,
  LandrixXmlTestFramework;

function U(const S: string): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(S);
end;

{ the bytes of A as UTF-8 text, without conversion }
function Raw(const A: AnsiString): TLandrixXmlUtf8;
begin
  Result := '';
  SetLength(Result, Length(A));
  if Length(A) > 0 then
    Move(A[1], Result[1], Length(A));
end;

function DataPath(const Name: string): string;
begin
  Result := IncludeTrailingPathDelimiter(RepositoryRoot) + 'tests' + PathDelim + 'data' + PathDelim + 'schematron' +
    PathDelim + Name;
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

function Lines(const FileName: string): TLandrixXmlUtf8Array;
var
  S: TLandrixXmlUtf8;
  I, Start, N: Integer;
begin
  Result := nil;
  S := FileBytes(FileName);
  N := 0;
  Start := 1;
  for I := 1 to Length(S) + 1 do
    if (I > Length(S)) or (S[I] = #10) then
    begin
      if I > Start then
      begin
        if N = Length(Result) then
          SetLength(Result, 2 * N + 64);
        Result[N] := Copy(S, Start, I - Start);
        if Result[N][Length(Result[N])] = #13 then
          SetLength(Result[N], Length(Result[N]) - 1);
        Inc(N);
      end;
      Start := I + 1;
    end;
  SetLength(Result, N);
end;

const
  KindText: array[TLandrixXmlSchematronResultKind] of string = ('failed-assert', 'successful-report',
    'dynamic-error');

{ The results of the last validation in the format of expected-*.txt. }
function ActualLines(V: TLandrixXmlSchematronValidator; out DynamicErrors: Integer): TLandrixXmlUtf8;
var
  I, P: Integer;
  R: TLandrixXmlSchematronResult;
  S: TLandrixXmlUtf8;
begin
  Result := '';
  DynamicErrors := 0;
  for I := 0 to V.FiredRules.Count - 1 do
  begin
    S := U(V.FiredRules[I]);
    { pattern TAB context TAB location: the context }
    P := Pos(#9, LandrixXmlUtf8ToString(S));
    S := Copy(S, P + 1, MaxInt);
    P := Pos(#9, LandrixXmlUtf8ToString(S));
    Result := Result + U('fired ') + Copy(S, 1, P - 1) + #10;
  end;
  for I := 0 to V.ResultCount - 1 do
  begin
    R := V.Results[I];
    if R.Kind = xsrDynamicError then
      Inc(DynamicErrors)
    else
      Result := Result + U(KindText[R.Kind] + ' ') + R.Id + ' ' + R.Flag + ' ' + R.Location + ' | ' + R.Message + #10;
  end;
end;

procedure RunSet(const Name, Syntax: string);
var
  Expected: TLandrixXmlUtf8Array;
  Rules: TLandrixXmlSchematronRules;
  V: TLandrixXmlSchematronValidator;
  I, Documents, Mismatches, Dynamic: Integer;
  Doc: string;
  Want, Got: TLandrixXmlUtf8;
  SaxonError: Boolean;
  Report: string;

  procedure Compare;
  begin
    if Doc = '' then
      Exit;
    Inc(Documents);
    V.ValidateFile(DataPath(Syntax + PathDelim + Doc));
    Got := ActualLines(V, Dynamic);
    if SaxonError then
    begin
      if not V.Incomplete or (Dynamic = 0) then
      begin
        Inc(Mismatches);
        Report := Report + #10 + '  ' + Doc + ': Saxon stops with a dynamic error, here none';
      end;
    end
    else if (Got <> Want) or (Dynamic > 0) then
    begin
      Inc(Mismatches);
      if Mismatches <= 5 then
        Report := Report + #10 + '  ' + Doc + ' (' + IntToStr(Dynamic) + ' dynamic errors)' + #10 + '  saxon:' + #10 +
          LandrixXmlUtf8ToString(Want) + '  got:' + #10 + LandrixXmlUtf8ToString(Got);
    end;
    Doc := '';
  end;

begin
  Expected := Lines(DataPath('expected-' + Name + '.txt'));
  Rules := TLandrixXmlSchematronRules.Create;
  V := nil;
  Documents := 0;
  Mismatches := 0;
  Report := '';
  Doc := '';
  Want := '';
  SaxonError := False;
  try
    Rules.LoadFromFile(DataPath('rules' + PathDelim + Name + '.xml'));
    V := TLandrixXmlSchematronValidator.Create(Rules);
    V.RecordFiredRules := True;
    for I := 0 to Integer(Length(Expected)) - 1 do
      if Copy(Expected[I], 1, 3) = '## ' then
      begin
        Compare;
        Doc := LandrixXmlUtf8ToString(Copy(Expected[I], 4, MaxInt));
        Want := '';
        SaxonError := False;
      end
      else if Copy(Expected[I], 1, 12) = 'saxon-error ' then
        SaxonError := True
      else
        Want := Want + Expected[I] + #10;
    Compare;
    Check(Documents >= 20, Name + ': documents present');
    Check(Mismatches = 0, Name + ': ' + IntToStr(Mismatches) + ' of ' + IntToStr(Documents) +
      ' documents differ from SchXslt:' + Report);
  finally
    V.Free;
    Rules.Free;
  end;
end;

procedure TestEn16931Ubl;
begin
  RunSet('en16931-ubl', 'ubl');
end;

procedure TestEn16931Cii;
begin
  RunSet('en16931-cii', 'cii');
end;

procedure TestXRechnungUbl;
begin
  RunSet('xrechnung-ubl', 'ubl');
end;

procedure TestXRechnungCii;
begin
  RunSet('xrechnung-cii', 'cii');
end;

{ DOM mode: the same results, with the DOM nodes. }
procedure TestDocument;
var
  Rules: TLandrixXmlSchematronRules;
  V: TLandrixXmlSchematronValidator;
  Doc: TLandrixXmlDocument;
  FromFile, FromDom: TLandrixXmlUtf8;
  I, D1, D2: Integer;
begin
  Rules := TLandrixXmlSchematronRules.Create;
  Doc := TLandrixXmlDocument.Create;
  V := nil;
  try
    Rules.LoadFromFile(DataPath('rules' + PathDelim + 'xrechnung-ubl.xml'));
    V := TLandrixXmlSchematronValidator.Create(Rules);
    Check(not V.ValidateFile(DataPath('ubl' + PathDelim + 'guide-example1.xml')), 'not a valid XRechnung');
    FromFile := ActualLines(V, D1);
    Check(V.ResultCount > 0, 'failed asserts');
    Doc.LoadFromFile(DataPath('ubl' + PathDelim + 'guide-example1.xml'));
    V.ValidateDocument(Doc);
    FromDom := ActualLines(V, D2);
    CheckEqualsUtf8(FromFile, FromDom, 'same results from the DOM');
    for I := 0 to V.ResultCount - 1 do
      Check(V.Results[I].Node <> nil, 'a DOM node for result ' + IntToStr(I));
    Check(V.Results[0].Line > 0, 'a line');
  finally
    V.Free;
    Doc.Free;
    Rules.Free;
  end;
end;

const
  Head = '<rules xmlns="urn:landrix:schematron-rules" format="1" source="t.sch" sha256="0" title="t">' +
    '<ns prefix="p" uri="urn:p"/>';

function SmallRules(const Body: string): TLandrixXmlSchematronRules;
begin
  Result := TLandrixXmlSchematronRules.Create;
  try
    Result.LoadFromUtf8(U(Head + Body + '</rules>'));
  except
    Result.Free;
    raise;
  end;
end;

{ First rule per pattern, unions with "|" in predicates, rooted contexts,
  flags, lets, functions, reports, abort on a dynamic error. }
procedure TestSmallRules;
var
  Rules: TLandrixXmlSchematronRules;
  V: TLandrixXmlSchematronValidator;
  Tree: TLandrixXmlXPathTree;
  S: string;
  I: Integer;
begin
  Rules := SmallRules(
    '<let name="g" value="count(//p:a)" line="1"/>' +
    '<function name="p:twice" as="xs:integer" line="2"><param name="x" as="xs:integer"/>' +
    '<variable name="y" as="" value="$x * 2"/><result value="$y"/></function>' +
    '<pattern id="A">' +
    '<rule context="p:a[(@k | @j) = ''x|y'']" id="" line="3">' +
    '<assert id="A1" flag="fatal" role="" test="false()" line="4"><text>first </text><name path=""/></assert></rule>' +
    '<rule context="p:a | /p:r" id="" line="5"><let name="n" value="local-name()"/>' +
    '<assert id="A2" flag="warning" role="" test="$n = ''none''" line="6"><text>name </text>' +
    '<value-of select="$n"/><text> of </text><value-of select="$g"/></assert>' +
    '<report id="A3" flag="information" role="" test="p:twice(1) = 2" line="7"><text>report</text></report></rule>' +
    '</pattern>' +
    '<pattern id="B"><rule context="p:a[2]" id="" line="8">' +
    '<assert id="B1" flag="fatal" role="" test="xs:integer(@k) = 2" line="9"><text>cast</text></assert>' +
    '<assert id="B2" flag="fatal" role="" test="false()" line="10"><text>after</text></assert></rule></pattern>');
  V := TLandrixXmlSchematronValidator.Create(Rules);
  Tree := TLandrixXmlXPathTree.Create;
  try
    Tree.LoadFromUtf8(U('<p:r xmlns:p="urn:p"><p:a k="x|y"/><p:a k="z"/><p:a k="3"/></p:r>'));
    Check(not V.ValidateTree(Tree), 'not valid');
    S := '';
    for I := 0 to V.ResultCount - 1 do
      S := S + LandrixXmlUtf8ToString(V.Results[I].Id + ' ' + V.Results[I].Flag + ' ' + V.Results[I].Location + ' ' +
        V.Results[I].Message) + ' / ';
    CheckEqualsStr(
      'A2 warning /Q{urn:p}r[1] name r of 3 / A3 information /Q{urn:p}r[1] report / ' +
      'A1 fatal /Q{urn:p}r[1]/Q{urn:p}a[1] first p:a / ' +
      'A2 warning /Q{urn:p}r[1]/Q{urn:p}a[2] name a of 3 / A3 information /Q{urn:p}r[1]/Q{urn:p}a[2] report / ' +
      'A2 warning /Q{urn:p}r[1]/Q{urn:p}a[3] name a of 3 / A3 information /Q{urn:p}r[1]/Q{urn:p}a[3] report / ' +
      'B1 fatal /Q{urn:p}r[1]/Q{urn:p}a[2] FORG0001: cannot convert ''z'' to xs:integer / ' +
      'B2 fatal /Q{urn:p}r[1]/Q{urn:p}a[2] after / ', S, 'results in order');
    CheckEquals(Ord(xsrDynamicError), Ord(V.Results[7].Kind), 'the cast is a dynamic error');
    CheckEqualsStr('FORG0001', V.Results[7].ErrorCode, 'its code');
    Check(V.Incomplete, 'incomplete');
    { as Saxon: stop at the first dynamic error }
    V.AbortOnDynamicError := True;
    V.ValidateTree(Tree);
    CheckEquals(8, V.ResultCount, 'stopped after the dynamic error');
    { warnings and information do not make a document invalid }
    Tree.LoadFromUtf8(U('<p:r xmlns:p="urn:p"/>'));
    V.AbortOnDynamicError := False;
    Check(V.ValidateTree(Tree), 'only a warning and a report: valid');
    CheckEquals(2, V.ResultCount, 'warning and report');
  finally
    Tree.Free;
    V.Free;
    Rules.Free;
  end;
end;

{ Variable names with prefixes and differing only in case, current() in a
  global and in a rule variable read from somewhere else, a document-node()
  context. }
procedure TestVariablesAndContexts;
var
  Rules: TLandrixXmlSchematronRules;
  V: TLandrixXmlSchematronValidator;
  Tree: TLandrixXmlXPathTree;
  S: string;
  I: Integer;
begin
  Rules := SmallRules(
    '<let name="g" value="1" line="1"/><let name="G" value="5" line="2"/>' +
    '<let name="p:g" value="2" line="3"/><let name="d" value="count(current()/p:r)" line="4"/>' +
    '<pattern id="A"><rule context="document-node()" id="" line="5">' +
    '<assert id="D" flag="fatal" role="" test="false()" line="6"><text>doc</text></assert></rule></pattern>' +
    '<pattern id="B"><rule context="p:a" id="" line="7">' +
    '<let name="p:n" value="string(@k)"/><let name="m" value="current()/@k"/>' +
    '<assert id="V" flag="fatal" role="" test="$g = 1 and $G = 5 and $p:g = 2 and $p:n = ''x'' and ' +
    'count(//p:a[@k = $m]) = 1 and $d = 1" line="8"><text>vars</text></assert></rule></pattern>');
  V := TLandrixXmlSchematronValidator.Create(Rules);
  Tree := TLandrixXmlXPathTree.Create;
  try
    Tree.LoadFromUtf8(U('<p:r xmlns:p="urn:p"><p:a k="x"/><p:a k="y"/></p:r>'));
    V.ValidateTree(Tree);
    S := '';
    for I := 0 to V.ResultCount - 1 do
      S := S + LandrixXmlUtf8ToString(V.Results[I].Id + ' ' + V.Results[I].Location + ' ' +
        V.Results[I].Message) + ' / ';
    CheckEqualsStr('D / doc / V /Q{urn:p}r[1]/Q{urn:p}a[2] vars / ', S, 'results');
  finally
    Tree.Free;
    V.Free;
    Rules.Free;
  end;
  { document-node() with predicates and spaces; prefixes bound to one URI
    name one variable; a non-ASCII function prefix; "current(" in a string }
  Rules := TLandrixXmlSchematronRules.Create;
  Rules.LoadFromUtf8(U(Head + '<ns prefix="q" uri="urn:p"/>') + Raw('<ns prefix="'#$C3#$A4'" uri="urn:u"/>' +
    '<function name="'#$C3#$A4':f" as="" line="1"><result value="7"/></function>') + U(
    '<pattern id="A"><rule context="document-node ( ) [p:r]" id="" line="2">' +
    '<assert id="D" flag="fatal" role="" test="false()" line="3"><text>doc</text></assert></rule></pattern>' +
    '<pattern id="B"><rule context="p:a" id="" line="4"><let name="p:n" value="string(@k)"/>' +
    '<assert id="N" flag="fatal" role="" test="$q:n = ''x''" line="5"><text>n</text></assert></rule></pattern>' +
    '<pattern id="C"><rule context="p:a[@k != ''current(''][1]" id="" line="6"><let name="q:n" value="1"/>' +
    '<assert id="F" flag="fatal" role="" test="$p:n = 2" line="7"><text>f</text></assert></rule></pattern>' +
    '</rules>'));
  V := TLandrixXmlSchematronValidator.Create(Rules);
  Tree := TLandrixXmlXPathTree.Create;
  try
    Tree.LoadFromUtf8(U('<p:r xmlns:p="urn:p"><p:a k="x"/><p:a k="y"/></p:r>'));
    V.ValidateTree(Tree);
    S := '';
    for I := 0 to V.ResultCount - 1 do
      S := S + LandrixXmlUtf8ToString(V.Results[I].Id + ' ' + V.Results[I].Location) + ' / ';
    CheckEqualsStr('D / / N /Q{urn:p}r[1]/Q{urn:p}a[2] / F /Q{urn:p}r[1]/Q{urn:p}a[1] / ', S, 'results');
  finally
    Tree.Free;
    V.Free;
    Rules.Free;
  end;
  { without rules the validator refuses to run }
  Rules := TLandrixXmlSchematronRules.Create;
  V := TLandrixXmlSchematronValidator.Create(Rules);
  Tree := TLandrixXmlXPathTree.Create;
  try
    Tree.LoadFromUtf8(U('<r/>'));
    try
      V.ValidateTree(Tree);
      FailNotRaised('no rules');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecInvalidOperation), Ord(E.Code), 'no rules: ' + E.Message);
    end;
  finally
    Tree.Free;
    V.Free;
    Rules.Free;
  end;
end;

procedure CheckLoadError(const Body: string; Code: TLandrixXmlErrorCode; const What: string);
var
  Rules: TLandrixXmlSchematronRules;
begin
  Rules := nil;
  try
    try
      Rules := SmallRules(Body);
      FailNotRaised(What);
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(Code), Ord(E.Code), What + ': ' + E.Message);
    end;
  finally
    Rules.Free;
  end;
end;

procedure TestLoadErrors;
var
  Rules: TLandrixXmlSchematronRules;
begin
  CheckLoadError('<pattern id="A"><rule context="p:a[" id="" line="r.sch:12"/></pattern>', xecXPath, 'bad context');
  CheckLoadError('<pattern id="A"><rule context="p:a" id="" line="1"><assert id="X" flag="" role="" ' +
    'test="unknown(1)" line="r.sch:20"/></rule></pattern>', xecXPath, 'unknown function');
  CheckLoadError('<let name="g" value="1" line="1"/><let name="g" value="2" line="2"/>', xecSchema, 'duplicate global');
  CheckLoadError('<let name="g" value="1" line="1"/><pattern id="A"><rule context="p:a" id="" line="1">' +
    '<let name="g" value="2"/></rule></pattern>', xecSchema, 'rule variable hides a global');
  CheckLoadError('<function name="p:f" as="xs:duration" line="1"><result value="1"/></function>', xecSchema,
    'unsupported type');
  CheckLoadError('<function name="p:f" as="" line="1"><param name="a" as=""/><result value="1"/></function>' +
    '<function name="p:f" as="" line="2"><param name="b" as=""/><result value="2"/></function>', xecSchema,
    'duplicate function');
  CheckLoadError('<pattern id="A"><rule context="p:a[@k = current ()/@k]" id="" line="1"/></pattern>',
    xecUnsupported, 'current() in a context');
  CheckLoadError('<pattern id="A"><rule context="document-node(element(p:r))" id="" line="1"/></pattern>',
    xecUnsupported, 'document-node() with an argument');
  CheckLoadError('<ns prefix="q" uri="urn:p"/><let name="p:g" value="1" line="1"/>' +
    '<function name="p:f" as="" line="2"><param name="q:g" as=""/><result value="$q:g"/></function>',
    xecSchema, 'a parameter hides a global through another prefix');
  CheckLoadError('<ns prefix="q" uri="urn:p"/><let name="p:g" value="1" line="1"/><let name="q:g" value="2" line="2"/>',
    xecSchema, 'one global through two prefixes');
  CheckLoadError('<ns prefix="q" uri="urn:p"/><pattern id="A">' +
    '<rule context="p:a" id="" line="1"><let name="p:n" value="0"/></rule>' +
    '<rule context="p:b" id="" line="2"><let name="p:n" value="1"/><let name="q:n" value="2"/></rule></pattern>',
    xecSchema, 'one rule variable twice, its slot allocated by an earlier rule');
  CheckLoadError('<pattern id="A"><rule context="(:c:) document-node()" id="" line="1"/></pattern>',
    xecUnsupported, 'a comment in a context');
  { the message of an XPath error names the line of the rule set }
  Rules := nil;
  try
    try
      Rules := SmallRules('<pattern id="A"><rule context="p:a[" id="" line="r.sch:12"/></pattern>');
    except
      on E: ELandrixXmlXPathError do
        Check(Pos('r.sch:12', E.Message) > 0, 'the line in the message: ' + E.Message);
    end;
  finally
    Rules.Free;
  end;
  Rules := TLandrixXmlSchematronRules.Create;
  try
    try
      Rules.LoadFromUtf8(U('<rules xmlns="urn:x" format="1"/>'));
      FailNotRaised('wrong root');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecSchema), Ord(E.Code), 'wrong root: ' + E.Message);
    end;
    CheckEquals(0, Rules.PatternCount, 'empty after a failed load');
    { a failed load also drops rules loaded before }
    Rules.LoadFromUtf8(U(Head + '<pattern id="A"/></rules>'));
    CheckEquals(1, Rules.PatternCount, 'loaded');
    try
      Rules.LoadFromUtf8(U('<rules'));
      FailNotRaised('malformed');
    except
      on ELandrixXmlError do
        CheckEquals(0, Rules.PatternCount, 'empty after a malformed file');
    end;
  finally
    Rules.Free;
  end;
end;

procedure Register;
begin
  RegisterTest('Schematron.EN16931Ubl', TestEn16931Ubl);
  RegisterTest('Schematron.EN16931Cii', TestEn16931Cii);
  RegisterTest('Schematron.XRechnungUbl', TestXRechnungUbl);
  RegisterTest('Schematron.XRechnungCii', TestXRechnungCii);
  RegisterTest('Schematron.Document', TestDocument);
  RegisterTest('Schematron.SmallRules', TestSmallRules);
  RegisterTest('Schematron.VariablesAndContexts', TestVariablesAndContexts);
  RegisterTest('Schematron.LoadErrors', TestLoadErrors);
end;

end.
