{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Tests for the schema loader and the validator: the cases in
  tests/data/xsdvalidator and its subfolder edge (expected results from
  the Xerces validator of the Java runtime,
  tools/gen-xsdvalidator-testdata.py) validated with the reader
  (positions compared) and with the DOM, plus load errors, unsupported
  constructs, paths and the error limit. }

unit LandrixXmlTestXsdValidator;

{$I LandrixXml.inc}

{$IFDEF LANDRIXXML_UNICODE}
  { DeleteFile is an inline routine on Delphi's POSIX targets and needs
    Posix.Unistd to be expanded (hint H2443); call it out of line. }
  {$INLINE OFF}
{$ENDIF}

interface

procedure Register;

implementation

uses
  SysUtils,
  Classes,
  LandrixXmlBase,
  LandrixXmlReader,
  LandrixXmlDom,
  LandrixXmlXsdSchema,
  LandrixXmlXsdSchemaLoader,
  LandrixXmlXsdValidator,
  LandrixXmlTestFramework;

function U(const S: string): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(S);
end;

function CaseFolder(const Name: string): string;
begin
  Result := IncludeTrailingPathDelimiter(RepositoryRoot) + 'tests' + PathDelim + 'data' + PathDelim +
    'xsdvalidator' + PathDelim + Name + PathDelim;
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

function Unescaped(const S: string): TLandrixXmlUtf8;
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
    if (S[I] = '\') and (I < Length(S)) then
    begin
      Inc(I);
      case S[I] of
        'n': Result[N] := #10;
        'r': Result[N] := #13;
        't': Result[N] := #9;
      else
        Result[N] := AnsiChar(S[I]);
      end;
    end
    else
      Result[N] := AnsiChar(S[I]);
    Inc(I);
  end;
  SetLength(Result, N);
end;

{ The errors of a validation as lines of expected.txt; WithPositions False
  leaves out line and column (DOM validation). }
function ErrorLines(V: TLandrixXmlXsdValidator; WithPositions: Boolean): string;
var
  I: Integer;
  E: TLandrixXmlXsdValidationError;
begin
  Result := '';
  for I := 0 to V.ErrorCount - 1 do
  begin
    E := V.Errors[I];
    if WithPositions then
      Result := Result + 'error ' + IntToStr(E.Line) + ' ' + IntToStr(E.Column) + ' ' + E.Code + ' ' +
        E.Message + #10
    else
      Result := Result + E.Code + ' ' + E.Message + #10;
  end;
end;

function WithoutPositions(const Lines: string): string;
var
  L: TStringList;
  I, P, Spaces: Integer;
  S: string;
begin
  Result := '';
  L := TStringList.Create;
  try
    L.Text := Lines;
    for I := 0 to L.Count - 1 do
    begin
      S := L[I];
      { drop "error LINE COLUMN " }
      Spaces := 0;
      P := 1;
      while (P <= Length(S)) and (Spaces < 3) do
      begin
        if S[P] = ' ' then
          Inc(Spaces);
        Inc(P);
      end;
      Result := Result + Copy(S, P, MaxInt) + #10;
    end;
  finally
    L.Free;
  end;
end;

procedure RunCase(const Name: string; MinDocuments: Integer);
var
  Schema: TLandrixXmlXsdSchemaSet;
  V: TLandrixXmlXsdValidator;
  Reader: TLandrixXmlReader;
  Doc: TLandrixXmlDocument;
  L: TStringList;
  K, Documents, Mismatches: Integer;
  Text: TLandrixXmlUtf8;
  Title, Expected, Got, Report: string;
  JdkException: Boolean;

  procedure Compare;
  var
    Ok: Boolean;
  begin
    if Title = '' then
      Exit;
    Inc(Documents);
    { reader }
    Reader := TLandrixXmlReader.Create;
    try
      Reader.LoadFromUtf8(Text);
      V.ValidateReader(Reader);
    finally
      Reader.Free;
    end;
    Got := ErrorLines(V, True);
    if JdkException then
      Ok := Pos('cvc-complex-type.2.4.d Invalid content was found starting with element', Got) > 0
    else
      Ok := Got = Expected;
    { DOM }
    Doc := TLandrixXmlDocument.Create;
    try
      Doc.LoadFromUtf8(Text);
      V.ValidateDocument(Doc);
    finally
      Doc.Free;
    end;
    if Ok and not JdkException then
      Ok := ErrorLines(V, False) = WithoutPositions(Expected);
    if not Ok then
    begin
      Inc(Mismatches);
      if Mismatches <= 10 then
        Report := Report + #10 + '  ' + Title + #10 + '  expected:' + #10 + Expected + '  got:' + #10 + Got +
          '  dom:' + #10 + ErrorLines(V, False);
    end;
    Title := '';
  end;

begin
  Documents := 0;
  Mismatches := 0;
  Report := '';
  Title := '';
  Schema := LandrixXmlXsdLoadSchema(CaseFolder(Name) + 'main.xsd');
  V := TLandrixXmlXsdValidator.Create(Schema);
  L := TStringList.Create;
  try
    V.MaxErrors := 0;
    L.LoadFromFile(CaseFolder(Name) + 'expected.txt');
    for K := 0 to L.Count - 1 do
    begin
      if Copy(L[K], 1, 5) = 'file ' then
      begin
        Compare;
        Title := L[K];
        Text := FileBytes(CaseFolder(Name) + Copy(L[K], 6, MaxInt));
        Expected := '';
        JdkException := False;
      end
      else if Copy(L[K], 1, 5) = 'text ' then
      begin
        Compare;
        Title := 'generated document ' + IntToStr(K + 1);
        Text := Unescaped(Copy(L[K], 6, MaxInt));
        Expected := '';
        JdkException := False;
      end
      else if Copy(L[K], 1, 6) = 'error ' then
        Expected := Expected + L[K] + #10
      else if L[K] = 'jdk-exception' then
        JdkException := True;
    end;
    Compare;
    Check(Documents >= MinDocuments, Name + ': documents present');
    Check(Mismatches = 0, Name + ': ' + IntToStr(Mismatches) + ' of ' + IntToStr(Documents) +
      ' documents differ from Xerces:' + Report);
  finally
    L.Free;
    V.Free;
    Schema.Free;
  end;
end;

procedure TestBasics;
begin
  RunCase('basics', 6);
end;

procedure TestDerivation;
begin
  RunCase('derivation', 6);
end;

procedure TestWildcards;
begin
  RunCase('wildcards', 6);
end;

procedure TestIdentity;
begin
  RunCase('identity', 6);
end;

procedure TestOccurrence;
begin
  RunCase('occurrence', 6);
end;

procedure TestValues;
begin
  RunCase('values', 6);
end;

{ Every folder in edge: one rule each, documents as Xerces judges them. }
procedure TestEdgeCases;
var
  SR: TSearchRec;
  Names: TStringList;
  I: Integer;
begin
  Names := TStringList.Create;
  try
    if FindFirst(CaseFolder('edge') + '*', faDirectory, SR) = 0 then
    try
      repeat
        if ((SR.Attr and faDirectory) <> 0) and (SR.Name <> '.') and (SR.Name <> '..') and
          FileExists(CaseFolder('edge' + PathDelim + SR.Name) + 'main.xsd') then
          Names.Add(SR.Name);
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
    Names.Sort;
    Check(Names.Count >= 50, 'edge cases present');
    for I := 0 to Names.Count - 1 do
      RunCase('edge' + PathDelim + Names[I], 1);
  finally
    Names.Free;
  end;
end;

{ --- load errors and API ---------------------------------------------------- }

function TempSchema(const Body: string; const RootAttributes: string = ''): string;
var
  F: TFileStream;
  S: TLandrixXmlUtf8;
begin
  { next to the test program, in the toolchain's build folder }
  Result := ExtractFilePath(ParamStr(0)) + 'xsdtest-' + IntToStr(Random(1000000)) + '.xsd';
  S := U('<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"' + RootAttributes + '>' + Body + '</xs:schema>');
  F := TFileStream.Create(Result, fmCreate);
  try
    F.WriteBuffer(S[1], Length(S));
  finally
    F.Free;
  end;
end;

procedure CheckLoadError(const Body: string; Code: TLandrixXmlErrorCode; const Name: string;
  const RootAttributes: string = '');
var
  FileName: string;
  S: TLandrixXmlXsdSchemaSet;
begin
  FileName := TempSchema(Body, RootAttributes);
  S := nil;
  try
    try
      S := LandrixXmlXsdLoadSchema(FileName);
      FailNotRaised('ELandrixXmlError for ' + Name);
    except
      on E: ELandrixXmlError do
      begin
        CheckEquals(Ord(Code), Ord(E.Code), Name + ': ' + E.Message);
        Check(Pos(ExtractFileName(FileName), E.Message) > 0, Name + ': the message names the file');
      end;
    end;
  finally
    S.Free;
    DeleteFile(FileName);
  end;
end;

procedure TestLoadErrors;
begin
  CheckLoadError('<xs:element name="r"><xs:complexType><xs:all><xs:element name="a"/></xs:all></xs:complexType></xs:element>',
    xecUnsupported, 'xs:all');
  CheckLoadError('<xs:simpleType name="l"><xs:list itemType="xs:int"/></xs:simpleType>' +
    '<xs:simpleType name="ll"><xs:list itemType="l"/></xs:simpleType>', xecSchema, 'a list of lists');
  CheckLoadError('<xs:element name="r" type="xs:ENTITIES"/>', xecUnsupported, 'xs:ENTITIES');
  CheckLoadError('<xs:element name="h"/><xs:element name="r" substitutionGroup="h"/>', xecUnsupported,
    'substitution group');
  CheckLoadError('<xs:element name="r" type="xs:duration"/>', xecUnsupported, 'xs:duration');
  CheckLoadError('<xs:element name="r" type="missing"/>', xecSchema, 'unknown type');
  CheckLoadError('<xs:element name="r"/><xs:element name="r"/>', xecSchema, 'duplicate element');
  CheckLoadError('<xs:element name="r"><xs:complexType><xs:sequence><xs:element ref="nothing"/></xs:sequence></xs:complexType></xs:element>',
    xecSchema, 'unknown element reference');
  CheckLoadError('<xs:simpleType name="t"><xs:restriction base="xs:int"><xs:maxLength value="2"/></xs:restriction></xs:simpleType>',
    xecSchema, 'facet not applicable');
  CheckLoadError('<xs:element name="r"><xs:complexType><xs:sequence><xs:element name="a" maxOccurs="0"/></xs:sequence>' +
    '</xs:complexType></xs:element>', xecSchema, 'minOccurs above maxOccurs');
  CheckLoadError('<xs:element name="r"><xs:complexType><xs:sequence><xs:element name="a" maxOccurs="$10"/>' +
    '</xs:sequence></xs:complexType></xs:element>', xecSchema, 'maxOccurs in hexadecimal');
  CheckLoadError('<xs:element name="r"><xs:complexType><xs:sequence><xs:element name="a" minOccurs="-1"/>' +
    '</xs:sequence></xs:complexType></xs:element>', xecSchema, 'negative minOccurs');
  CheckLoadError('<xs:element name="r"><xs:complexType><xs:sequence><xs:element name="a" minOccurs="+"/>' +
    '</xs:sequence></xs:complexType></xs:element>', xecSchema, 'sign without digits');
  CheckLoadError('<xs:element name="r"><xs:complexType><xs:sequence><xs:element name="a" minOccurs="99999999999" ' +
    'maxOccurs="99999999998"/></xs:sequence></xs:complexType></xs:element>', xecSchema,
    'minOccurs above maxOccurs beyond Integer');
  CheckLoadError('<xs:element name="r"><xs:complexType><xs:sequence><xs:element name="a" ' +
    'minOccurs="99999999999999999999" maxOccurs="099999999999999999998"/></xs:sequence></xs:complexType>' +
    '</xs:element>', xecSchema, 'minOccurs above maxOccurs beyond Int64');
  { with a target namespace the union of ##other and ##local is not
    expressible in XML Schema 1.0 }
  CheckLoadError('<xs:complexType name="b"><xs:anyAttribute namespace="##other"/></xs:complexType>' +
    '<xs:element name="r"><xs:complexType><xs:complexContent><xs:extension base="p:b">' +
    '<xs:anyAttribute namespace="##local"/></xs:extension></xs:complexContent></xs:complexType></xs:element>',
    xecSchema, 'wildcard union', ' xmlns:p="urn:p" targetNamespace="urn:p"');
end;

{ A keyref whose key ended in a sibling: Xerces has no cvc code for it and
  names the constraint by its Java object, so this is checked here. }
procedure TestKeyRefOutOfScope;
var
  FileName: string;
  S: TLandrixXmlXsdSchemaSet;
  V: TLandrixXmlXsdValidator;
  Reader: TLandrixXmlReader;
begin
  FileName := TempSchema('<xs:element name="R"><xs:complexType><xs:sequence>' +
    '<xs:element name="S1"><xs:complexType><xs:sequence><xs:element name="item" maxOccurs="unbounded">' +
    '<xs:complexType><xs:attribute name="id" type="xs:string"/></xs:complexType></xs:element></xs:sequence>' +
    '</xs:complexType><xs:key name="K"><xs:selector xpath="item"/><xs:field xpath="@id"/></xs:key></xs:element>' +
    '<xs:element name="S2" maxOccurs="unbounded"><xs:complexType><xs:sequence><xs:element name="ref" minOccurs="0" maxOccurs="unbounded">' +
    '<xs:complexType><xs:attribute name="to" type="xs:string"/></xs:complexType></xs:element></xs:sequence>' +
    '</xs:complexType><xs:keyref name="KR" refer="K"><xs:selector xpath="ref"/><xs:field xpath="@to"/></xs:keyref>' +
    '</xs:element></xs:sequence></xs:complexType></xs:element>');
  S := LandrixXmlXsdLoadSchema(FileName);
  V := TLandrixXmlXsdValidator.Create(S);
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromUtf8(U('<R><S1><item id="1"/></S1><S2><ref to="1"/></S2></R>'));
    Check(not V.ValidateReader(Reader), 'out of scope');
    CheckEquals(1, V.ErrorCount, 'one error');
    CheckEqualsStr('KeyRefOutOfScope', V.Errors[0].Code, 'code');
    CheckEqualsStr('Identity Constraint error:  identity constraint "KR" has a keyref which refers to a key or ' +
      'unique that is out of scope.', V.Errors[0].Message, 'message');
    CheckEquals(1, V.Errors[0].Line, 'line');
    CheckEquals(49, V.Errors[0].Column, 'column after </S2>');
    { the store of the keyref is reused for the next S2: Xerces checks it
      again although it is empty }
    Reader.LoadFromUtf8(U('<R><S1><item id="1"/></S1><S2><ref to="1"/></S2><S2/></R>'));
    V.ValidateReader(Reader);
    CheckEquals(2, V.ErrorCount, 'reported again for the empty S2');
    CheckEquals(54, V.Errors[1].Column, 'column after <S2/>');
  finally
    Reader.Free;
    V.Free;
    S.Free;
    DeleteFile(FileName);
  end;
end;

procedure TestApi;
var
  FileName: string;
  S: TLandrixXmlXsdSchemaSet;
  V: TLandrixXmlXsdValidator;
  Reader: TLandrixXmlReader;
  I: Integer;
  Xml: TLandrixXmlUtf8;
begin
  FileName := TempSchema('<xs:element name="r"><xs:complexType><xs:sequence>' +
    '<xs:element name="a" type="xs:int" maxOccurs="unbounded"/></xs:sequence></xs:complexType></xs:element>');
  S := LandrixXmlXsdLoadSchema(FileName);
  V := TLandrixXmlXsdValidator.Create(S);
  Reader := TLandrixXmlReader.Create;
  try
    Xml := '<r><a>1</a><a>x</a><a>2</a><a>y</a></r>';
    Reader.LoadFromUtf8(Xml);
    Check(not V.ValidateReader(Reader), 'invalid');
    CheckEquals(4, V.ErrorCount, 'two errors per bad value');
    CheckEqualsUtf8(U('/r/a[2]'), V.Errors[0].Path, 'path of the second a');
    CheckEqualsUtf8(U('/r/a[4]'), V.Errors[2].Path, 'path of the fourth a');
    Check(V.Errors[0].SchemaLine > 0, 'schema line');
    { the loader keeps the expanded file name }
    CheckEqualsStr(ExpandFileName(FileName), V.Errors[0].SchemaFile, 'schema file');
    Check(not V.Truncated, 'not truncated');
    V.MaxErrors := 1;
    Reader.LoadFromUtf8(Xml);
    V.ValidateReader(Reader);
    CheckEquals(1, V.ErrorCount, 'limited');
    Check(V.Truncated, 'truncated');
    { xsi:type is reported, never ignored }
    V.MaxErrors := 0;
    Xml := '<r xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><a xsi:type="xs:int">1</a></r>';
    Reader.LoadFromUtf8(Xml);
    Check(not V.ValidateReader(Reader), 'xsi:type');
    Check(V.ErrorCount > 0, 'an error for xsi:type');
    CheckEqualsStr('unsupported', V.Errors[0].Code, 'xsi:type is unsupported');
    for I := 0 to V.ErrorCount - 1 do
      Check(V.Errors[I].Code <> '', 'every error has a code');
  finally
    Reader.Free;
    V.Free;
    S.Free;
    DeleteFile(FileName);
  end;
end;

{ minOccurs and maxOccurs as xs:nonNegativeInteger: a sign, leading zeros
  and values beyond Integer (an upper bound there is out of reach) }
procedure TestLargeOccurs;
var
  FileName: string;
  S: TLandrixXmlXsdSchemaSet;
  V: TLandrixXmlXsdValidator;
  Reader: TLandrixXmlReader;
begin
  FileName := TempSchema('<xs:element name="r"><xs:complexType><xs:sequence>' +
    '<xs:element name="a" minOccurs="+002" maxOccurs="12678967543234"/>' +
    '<xs:element name="b" minOccurs="-0" maxOccurs="99999999999999999999999"/>' +
    '</xs:sequence></xs:complexType></xs:element>');
  S := LandrixXmlXsdLoadSchema(FileName);
  V := TLandrixXmlXsdValidator.Create(S);
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromUtf8(U('<r><a/><a/><a/><b/></r>'));
    Check(V.ValidateReader(Reader), 'three a, one b');
    Reader.LoadFromUtf8(U('<r><a/></r>'));
    Check(not V.ValidateReader(Reader), 'one a is below minOccurs="+002"');
  finally
    Reader.Free;
    V.Free;
    S.Free;
    DeleteFile(FileName);
  end;
end;

{ an include, import or redefine whose document cannot be found is
  skipped with a warning (XML Schema 1.0 4.2.1, as Xerces) }
procedure CheckSkipped(const Body, Expected: string; WarningCount: Integer);
var
  FileName: string;
  S: TLandrixXmlXsdSchemaSet;
begin
  FileName := TempSchema(Body);
  S := nil;
  try
    S := LandrixXmlXsdLoadSchema(FileName);
    CheckEquals(WarningCount, Integer(S.Warnings.Count), Expected + ': warnings');
    if WarningCount > 0 then
    begin
      Check(Pos(Expected, S.Warnings[0]) > 0, Expected + ': ' + S.Warnings[0]);
      Check(Pos(ExtractFileName(FileName), S.Warnings[0]) > 0, Expected + ': the warning names the file');
    end;
  finally
    S.Free;
    DeleteFile(FileName);
  end;
end;

procedure WriteTestFile(const FileName, Content: string);
var
  F: TFileStream;
  S: TLandrixXmlUtf8;
begin
  S := U(Content);
  F := TFileStream.Create(FileName, fmCreate);
  try
    F.WriteBuffer(S[1], Length(S));
  finally
    F.Free;
  end;
end;

procedure TestUnresolved;
var
  FileName: string;
  S: TLandrixXmlXsdSchemaSet;
begin
  CheckSkipped('<xs:include schemaLocation="missing-include.xsd"/><xs:element name="r"/>',
    'the include of "missing-include.xsd"', 1);
  CheckSkipped('<xs:include schemaLocation="http://example.org/x.xsd"/><xs:element name="r"/>',
    'the include of "http://example.org/x.xsd"', 1);
  CheckSkipped('<xs:redefine schemaLocation="missing-redefine.xsd"><xs:annotation/></xs:redefine>' +
    '<xs:element name="r"/>', 'the redefine of "missing-redefine.xsd"', 1);
  CheckSkipped('<xs:import namespace="urn:x" schemaLocation="missing-import.xsd"/><xs:element name="r"/>',
    'the import of urn:x (missing-import.xsd', 1);
  { an import without schemaLocation is resolved by the catalog or not at all }
  CheckSkipped('<xs:import namespace="urn:x"/><xs:element name="r"/>', '', 0);
  CheckSkipped('<xs:import namespace="urn:x" schemaLocation=""/><xs:element name="r"/>',
    'the import of urn:x (, ', 1);
  { a redefine that redefines something must resolve (4.2.2) }
  CheckLoadError('<xs:redefine schemaLocation="missing-redefine.xsd"><xs:simpleType name="t">' +
    '<xs:restriction base="t"/></xs:simpleType></xs:redefine>', xecSchema, 'redefine with content');
  CheckLoadError('<xs:include schemaLocation="missing-include.xsd"><xs:annotation/><xs:annotation/>' +
    '</xs:include>', xecSchema, 'two annotations in xs:include');
  CheckLoadError('<xs:import namespace="urn:x"><xs:element name="e"/></xs:import>', xecSchema,
    'an element in xs:import');
  { a reference into a skipped include names it }
  FileName := TempSchema('<xs:include schemaLocation="missing-include.xsd"/><xs:element name="r" type="t"/>');
  S := nil;
  try
    try
      S := LandrixXmlXsdLoadSchema(FileName);
      FailNotRaised('ELandrixXmlError for a type of a skipped include');
    except
      on E: ELandrixXmlError do
      begin
        CheckEquals(Ord(xecSchema), Ord(E.Code), E.Message);
        Check(Pos('the include of "missing-include.xsd"', E.Message) > 0, 'names the include: ' + E.Message);
      end;
    end;
  finally
    S.Free;
    DeleteFile(FileName);
  end;
end;

{$IFDEF MSWINDOWS}
{ the same document under a differently cased name (XSTS schZ012) is one
  document on Windows (Linux decides by the mounted file system) }
procedure TestFileCase;
var
  A, B: string;
  S: TLandrixXmlXsdSchemaSet;
begin
  A := ExtractFilePath(ParamStr(0)) + 'xsdcase-a.xsd';
  B := ExtractFilePath(ParamStr(0)) + 'xsdcase-b.xsd';
  WriteTestFile(A, '<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:a">' +
    '<xs:import schemaLocation="xsdcase-b.xsd"/><xs:element name="root"/></xs:schema>');
  WriteTestFile(B, '<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">' +
    '<xs:import namespace="urn:a" schemaLocation="XSDCASE-A.xsd"/><xs:element name="b"/></xs:schema>');
  S := nil;
  try
    S := LandrixXmlXsdLoadSchema(A);
    Check(S.FindElement('urn:a', 'root') <> nil, 'root');
    CheckEquals(2, Integer(S.Files.Count), 'two documents');
    CheckEquals(0, Integer(S.Warnings.Count), 'no warning');
  finally
    S.Free;
    DeleteFile(A);
    DeleteFile(B);
  end;
end;
{$ENDIF}

{ the schema for schemas: the constraint code Xerces reports and the
  position of the offending element }
procedure CheckSchemaRule(const Body, ConstraintCode: string; Line: Integer; const Name: string;
  const RootAttributes: string = '');
var
  FileName: string;
  S: TLandrixXmlXsdSchemaSet;
begin
  FileName := TempSchema(Body, RootAttributes);
  S := nil;
  try
    try
      S := LandrixXmlXsdLoadSchema(FileName);
      FailNotRaised('ELandrixXmlXsdSchemaError for ' + Name);
    except
      on E: ELandrixXmlXsdSchemaError do
      begin
        CheckEquals(Ord(xecSchema), Ord(E.Code), Name + ': ' + E.Message);
        CheckEqualsStr(ConstraintCode, E.ConstraintCode, Name + ': ' + E.Message);
        CheckEqualsStr(ExpandFileName(FileName), E.SchemaFile, Name + ': schema file');
        CheckEquals(Line, E.Line, Name + ': line');
        Check(E.Column > 0, Name + ': column');
      end;
    end;
  finally
    S.Free;
    DeleteFile(FileName);
  end;
end;

procedure TestSchemaRules;
var
  FileName: string;
  S: TLandrixXmlXsdSchemaSet;
begin
  CheckSchemaRule('<xs:element name="r" maxOccur="2"/>', 's4s-att-not-allowed', 1, 'unknown attribute');
  CheckSchemaRule('<xs:element name="r" xs:type="xs:int"/>', 's4s-att-not-allowed', 1,
    'attribute in the XML Schema namespace');
  CheckSchemaRule('<xs:element name="1r"/>', 's4s-att-invalid-value', 1, 'name not an NCName');
  CheckSchemaRule('<xs:element name="r" nillable="yes"/>', 's4s-att-invalid-value', 1, 'boolean');
  CheckSchemaRule('<xs:complexType name="t" block="all"/>', 's4s-att-invalid-value', 1, 'derivation set');
  CheckSchemaRule('<xs:element name="r"><xs:complexType><xs:sequence><xs:any namespace="##others"/>' +
    '</xs:sequence></xs:complexType></xs:element>', 's4s-att-invalid-value', 1, 'namespace list');
  CheckSchemaRule('<xs:element name="a" id="x"/><xs:element name="b" id="x"/>', 's4s-att-invalid-value', 1,
    'duplicate id');
  CheckSchemaRule('<xs:element/>', 's4s-att-must-appear', 1, 'top-level element without name');
  CheckSchemaRule('<xs:element name="r"><xs:complexType><xs:sequence><xs:element ref="r" name="x"/>' +
    '</xs:sequence></xs:complexType></xs:element>', 's4s-att-not-allowed', 1, 'name besides ref');
  CheckSchemaRule('<xs:element name="r"><xs:complexType><xs:attribute name="a"/><xs:sequence/>' +
    '</xs:complexType></xs:element>', 's4s-elt-must-match.1', 1, 'particle after an attribute');
  CheckSchemaRule('<xs:element name="r"><xs:annotation/><xs:annotation/></xs:element>', 's4s-elt-must-match.1', 1,
    'two annotations');
  CheckSchemaRule('<xs:simpleType name="s"><xs:restriction base="xs:int"><xs:sequence/></xs:restriction>' +
    '</xs:simpleType>', 's4s-elt-invalid-content.1', 1, 'a particle in a simple type');
  CheckSchemaRule('<xs:element name="r"/>' + #10 + '<xs:group name="g"/>', 's4s-elt-must-match.1', 2,
    'a group without a compositor');
  CheckSchemaRule('<xs:element name="r">text</xs:element>', 's4s-elt-character', 1, 'character data');
  CheckSchemaRule('<xs:element name="r"><xs:annotation><xs:documentation xml:lang="">x</xs:documentation>' +
    '</xs:annotation></xs:element>', 's4s-att-invalid-value', 1, 'empty xml:lang');
  CheckSchemaRule('<xs:element name="r" type="xs: string"/>', 's4s-att-invalid-value', 1, 'space in a QName');
  CheckSchemaRule('<xs:element name="r"><xs:key name="k"><xs:selector xpath="a"/><xs:field xpath="@b"/></xs:key>' +
    '<xs:keyref name="kr" refer="missing"><xs:selector xpath="a"/><xs:field xpath="@b"/></xs:keyref></xs:element>',
    'src-resolve', 1, 'keyref to no key');
  CheckSchemaRule('<xs:simpleType name="s"><xs:restriction base="xs:string"><xs:minLength value="3"/>' +
    '<xs:maxLength value="2"/></xs:restriction></xs:simpleType>', 'minLength-less-than-equal-to-maxLength', 1,
    'inconsistent facets');
  CheckSchemaRule('<xs:simpleType name="s"><xs:restriction base="xs:string"><xs:maxLength value="3" ' +
    'fixed="true"/></xs:restriction></xs:simpleType>' + #10 + '<xs:simpleType name="t"><xs:restriction base="s">' +
    '<xs:maxLength value="2"/></xs:restriction></xs:simpleType>', 'FixedFacetValue', 2, 'fixed facet');
  CheckSchemaRule('<xs:element name="r"/>' + #10 + '<xs:complexType name="t"><xs:sequence>' +
    '<xs:element name="a" minOccurs="0"/><xs:element name="a"/></xs:sequence></xs:complexType>',
    'cos-nonambig', 2, 'ambiguous content model');
  CheckSchemaRule('<xs:element name="r"><xs:complexType><xs:choice><xs:any namespace="##any"/>' +
    '<xs:element ref="r"/></xs:choice></xs:complexType></xs:element>', 'cos-nonambig', 1,
    'a wildcard competing with an element');
  { element and attribute declarations }
  CheckSchemaRule('<xs:element name="r" type="xs:int" default="x"/>', 'e-props-correct.2', 1, 'invalid element default');
  CheckSchemaRule('<xs:element name="r" fixed="x"><xs:complexType><xs:sequence><xs:element name="a"/>' +
    '</xs:sequence></xs:complexType></xs:element>', 'e-props-correct.2', 1, 'fixed value of element-only content');
  CheckSchemaRule('<xs:element name="r" fixed="x"><xs:complexType mixed="true"><xs:sequence>' +
    '<xs:element name="a"/></xs:sequence></xs:complexType></xs:element>', 'e-props-correct.2', 1,
    'fixed value of mixed content that is not emptiable');
  CheckSchemaRule('<xs:element name="r" type="xs:ID" default="x"/>', 'e-props-correct.5', 1, 'default of an ID element');
  CheckSchemaRule('<xs:element name="r"/>' + #10 + '<xs:attribute name="a" type="xs:int" default="x"/>',
    'cvc-datatype-valid.1.2.1', 2, 'invalid attribute default');
  CheckSchemaRule('<xs:attribute name="a" type="xs:ID" fixed="x"/>', 'a-props-correct.3', 1, 'fixed ID attribute');
  CheckSchemaRule('<xs:element name="r"><xs:complexType><xs:attribute name="a" default="x" use="required"/>' +
    '</xs:complexType></xs:element>', 'src-attribute.2', 1, 'default with use required');
  CheckSchemaRule('<xs:attribute name="a" type="xs:int" fixed="1"/><xs:element name="r"><xs:complexType>' +
    '<xs:attribute ref="a" fixed="2"/></xs:complexType></xs:element>', 'au-props-correct.2', 1,
    'a use with another fixed value');
  CheckSchemaRule('<xs:attribute name="a" type="xs:int" fixed="1"/><xs:element name="r"><xs:complexType>' +
    '<xs:attribute ref="a" default="1"/></xs:complexType></xs:element>', 'au-props-correct.2', 1,
    'a use with a default for a fixed declaration');
  CheckSchemaRule('<xs:attribute name="xmlns"/>', 'no-xmlns', 1, 'attribute xmlns');
  CheckSchemaRule('<xs:attribute name="a"/>', 'no-xsi', 1, 'attribute in the xsi namespace',
    ' targetNamespace="http://www.w3.org/2001/XMLSchema-instance"');
  CheckSchemaRule('<xs:element name="r"><xs:complexType><xs:sequence><xs:element name="a" type="xs:int"/>' +
    '<xs:element name="a" type="xs:string" minOccurs="0"/></xs:sequence></xs:complexType></xs:element>',
    'cos-element-consistent', 1, 'two elements a with different types');
  { type derivations }
  CheckSchemaRule('<xs:complexType name="b" final="extension"/><xs:complexType name="d"><xs:complexContent>' +
    '<xs:extension base="b"/></xs:complexContent></xs:complexType>',
    'cos-ct-extends.1.1', 1, 'extension of a final type');
  CheckSchemaRule('<xs:complexType name="b"/><xs:complexType name="d"><xs:complexContent>' +
    '<xs:restriction base="b"/></xs:complexContent></xs:complexType>',
    'derivation-ok-restriction.1', 1, 'restriction forbidden by finalDefault', ' finalDefault="restriction"');
  CheckSchemaRule('<xs:simpleType name="s" final="#all"><xs:restriction base="xs:int"/></xs:simpleType>' +
    '<xs:complexType name="d"><xs:simpleContent><xs:extension base="s"/></xs:simpleContent>' +
    '</xs:complexType>',
    'cos-ct-extends.1.1', 1, 'simple content extending a final simple type');
  CheckSchemaRule('<xs:simpleType name="s" final="restriction"><xs:restriction base="xs:int"/></xs:simpleType>' +
    '<xs:simpleType name="t"><xs:restriction base="s"/></xs:simpleType>',
    'st-props-correct.3', 1, 'restriction of a final simple type');
  CheckSchemaRule('<xs:simpleType name="s" final="list"><xs:restriction base="xs:int"/></xs:simpleType>' +
    '<xs:simpleType name="t"><xs:list itemType="s"/></xs:simpleType>',
    'cos-st-restricts.2.3.1.1', 1, 'list of a final item type');
  CheckSchemaRule('<xs:simpleType name="s"><xs:restriction base="xs:int"/></xs:simpleType>' +
    '<xs:simpleType name="t"><xs:union memberTypes="xs:date s"/></xs:simpleType>',
    'cos-st-restricts.3.3.1.1', 1, 'union of a final member type', ' finalDefault="union"');
  CheckSchemaRule('<xs:simpleType name="s"><xs:restriction base="xs:anySimpleType"/></xs:simpleType>',
    'cos-st-restricts.1.1', 1, 'restriction of xs:anySimpleType');
  CheckSchemaRule('<xs:complexType name="d"><xs:simpleContent><xs:restriction base="xs:int"/></xs:simpleContent>' +
    '</xs:complexType>',
    'src-ct.2.1', 1, 'simple content restricting a simple type');
  CheckSchemaRule('<xs:complexType name="b"><xs:sequence><xs:element name="x"/></xs:sequence></xs:complexType>' +
    '<xs:complexType name="d"><xs:simpleContent><xs:extension base="b"/></xs:simpleContent>' +
    '</xs:complexType>',
    'src-ct.2.1', 1, 'simple content extending element-only content');
  CheckSchemaRule('<xs:complexType name="b" mixed="true"><xs:sequence><xs:element name="x"/></xs:sequence>' +
    '</xs:complexType><xs:complexType name="d"><xs:simpleContent><xs:restriction base="b">' +
    '<xs:simpleType><xs:restriction base="xs:int"/></xs:simpleType></xs:restriction>' +
    '</xs:simpleContent></xs:complexType>',
    'src-ct.2.1', 1, 'simple content restricting mixed content that is not emptiable');
  CheckSchemaRule('<xs:complexType name="b"><xs:simpleContent><xs:extension base="xs:int"/></xs:simpleContent>' +
    '</xs:complexType><xs:complexType name="d"><xs:simpleContent><xs:restriction base="b">' +
    '<xs:simpleType><xs:restriction base="xs:string"/></xs:simpleType></xs:restriction>' +
    '</xs:simpleContent></xs:complexType>',
    'derivation-ok-restriction.5.2.2.1', 1, 'local simple type not derived from the base');
  CheckSchemaRule('<xs:complexType name="b" mixed="true"><xs:sequence><xs:element name="x"/></xs:sequence>' +
    '</xs:complexType><xs:complexType name="d"><xs:complexContent><xs:extension base="b">' +
    '<xs:sequence><xs:element name="y"/></xs:sequence></xs:extension></xs:complexContent>' +
    '</xs:complexType>',
    'cos-ct-extends.1.4.3.2.2.1.a', 1, 'element-only extension of mixed content');
  CheckSchemaRule('<xs:complexType name="b"><xs:simpleContent><xs:extension base="xs:int"/></xs:simpleContent>' +
    '</xs:complexType><xs:complexType name="d"><xs:complexContent><xs:extension base="b">' +
    '<xs:sequence><xs:element name="y"/></xs:sequence></xs:extension></xs:complexContent>' +
    '</xs:complexType>',
    'cos-ct-extends.1.4.3.2.2.1.a', 1, 'element-only extension of simple content');
  CheckSchemaRule('<xs:complexType name="b"><xs:sequence><xs:element name="x"/></xs:sequence></xs:complexType>' +
    '<xs:complexType name="d" mixed="true"><xs:complexContent><xs:extension base="b"/>' +
    '</xs:complexContent></xs:complexType>',
    'cos-ct-extends.1.4.3.2.2.1.b', 1, 'mixed extension of element-only content');
  CheckSchemaRule('<xs:complexType name="b"><xs:sequence><xs:element name="x"/></xs:sequence></xs:complexType>' +
    '<xs:complexType name="d"><xs:complexContent mixed="true"><xs:restriction base="b">' +
    '<xs:sequence><xs:element name="x"/></xs:sequence></xs:restriction></xs:complexContent>' +
    '</xs:complexType>',
    'derivation-ok-restriction.5.4.1.2', 1, 'mixed restriction of element-only content');
  CheckSchemaRule('<xs:complexType name="d"><xs:attribute name="a" type="xs:ID"/>' +
    '<xs:attribute name="c" type="xs:ID"/></xs:complexType>',
    'ct-props-correct.5', 1, 'two ID attributes');
  CheckSchemaRule('<xs:complexType name="b"><xs:attribute name="a" type="xs:ID"/></xs:complexType>' +
    '<xs:complexType name="d"><xs:complexContent><xs:extension base="b">' +
    '<xs:attribute name="c" type="xs:ID"/></xs:extension></xs:complexContent></xs:complexType>',
    'ct-props-correct.5', 1, 'an ID attribute added to one of the base');
  CheckSchemaRule('<xs:complexType name="b"><xs:attribute name="a" use="required"/></xs:complexType>' +
    '<xs:complexType name="d"><xs:complexContent><xs:restriction base="b"><xs:attribute name="a"/>' +
    '</xs:restriction></xs:complexContent></xs:complexType>',
    'derivation-ok-restriction.2.1.1', 1, 'a required attribute made optional');
  CheckSchemaRule('<xs:complexType name="b"><xs:attribute name="a" type="xs:int"/></xs:complexType>' +
    '<xs:complexType name="d"><xs:complexContent><xs:restriction base="b">' +
    '<xs:attribute name="a" type="xs:string"/></xs:restriction></xs:complexContent></xs:complexType>',
    'derivation-ok-restriction.2.1.2', 1, 'an attribute type not derived from the base one');
  CheckSchemaRule('<xs:complexType name="b"><xs:attribute name="a" type="xs:int" fixed="1"/></xs:complexType>' +
    '<xs:complexType name="d"><xs:complexContent><xs:restriction base="b">' +
    '<xs:attribute name="a" type="xs:int"/></xs:restriction></xs:complexContent></xs:complexType>',
    'derivation-ok-restriction.2.1.3.a', 1, 'a fixed attribute no longer fixed');
  CheckSchemaRule('<xs:complexType name="b"><xs:attribute name="a" type="xs:int" fixed="1"/></xs:complexType>' +
    '<xs:complexType name="d"><xs:complexContent><xs:restriction base="b">' +
    '<xs:attribute name="a" type="xs:int" fixed="2"/></xs:restriction></xs:complexContent>' +
    '</xs:complexType>',
    'derivation-ok-restriction.2.1.3.b', 1, 'a fixed attribute with another value');
  CheckSchemaRule('<xs:complexType name="b"></xs:complexType><xs:complexType name="d"><xs:complexContent>' +
    '<xs:restriction base="b"><xs:attribute name="a"/></xs:restriction></xs:complexContent>' +
    '</xs:complexType>',
    'derivation-ok-restriction.2.2.a', 1, 'a new attribute without a base wildcard');
  CheckSchemaRule('<xs:complexType name="b"><xs:anyAttribute namespace="##other"/></xs:complexType>' +
    '<xs:complexType name="d"><xs:complexContent><xs:restriction base="b"><xs:attribute name="a"/>' +
    '</xs:restriction></xs:complexContent></xs:complexType>',
    'derivation-ok-restriction.2.2.b', 1, 'a new attribute the base wildcard does not allow');
  CheckSchemaRule('<xs:complexType name="b"><xs:attribute name="a" use="required"/></xs:complexType>' +
    '<xs:complexType name="d"><xs:complexContent><xs:restriction base="b">' +
    '<xs:attribute name="a" use="prohibited"/></xs:restriction></xs:complexContent></xs:complexType>',
    'derivation-ok-restriction.3', 1, 'a required attribute prohibited');
  CheckSchemaRule('<xs:complexType name="b"></xs:complexType><xs:complexType name="d"><xs:complexContent>' +
    '<xs:restriction base="b"><xs:anyAttribute/></xs:restriction></xs:complexContent>' +
    '</xs:complexType>',
    'derivation-ok-restriction.4.1', 1, 'a wildcard without a base wildcard');
  CheckSchemaRule('<xs:complexType name="b"><xs:anyAttribute namespace="##other"/></xs:complexType>' +
    '<xs:complexType name="d"><xs:complexContent><xs:restriction base="b"><xs:anyAttribute/>' +
    '</xs:restriction></xs:complexContent></xs:complexType>',
    'derivation-ok-restriction.4.2', 1, 'a wildcard that is no subset');
  CheckSchemaRule('<xs:complexType name="b"><xs:anyAttribute processContents="lax"/></xs:complexType>' +
    '<xs:complexType name="d"><xs:complexContent><xs:restriction base="b">' +
    '<xs:anyAttribute processContents="skip"/></xs:restriction></xs:complexContent></xs:complexType>',
    'derivation-ok-restriction.4.3', 1, 'a wildcard with weaker processContents');
  CheckSchemaRule('<xs:simpleType name="custom"><xs:restriction base="xs:anySimpleType"/></xs:simpleType>',
    'cos-st-restricts.1.1', 1, 'restriction of xs:anySimpleType in the XML Schema namespace', ' targetNamespace="http://www.w3.org/2001/XMLSchema"');
  CheckSchemaRule('<xs:simpleType name="inner"><xs:union memberTypes="xs:int xs:string"/></xs:simpleType>' +
    '<xs:simpleType name="outer"><xs:union memberTypes="inner xs:boolean"/></xs:simpleType>' +
    '<xs:complexType name="b"><xs:attribute name="a" type="outer"/></xs:complexType>' +
    '<xs:complexType name="d"><xs:complexContent><xs:restriction base="b">' +
    '<xs:attribute name="a" type="inner"/></xs:restriction></xs:complexContent></xs:complexType>',
    'derivation-ok-restriction.2.1.2', 1, 'an attribute type that is a member union of the base one');
  { valid forms the rules must accept }
  FileName := TempSchema('<xs:annotation><xs:documentation xml:lang="de">x</xs:documentation></xs:annotation>' +
    '<xs:element name="r" id="e1"><xs:complexType mixed="true"><xs:sequence minOccurs="0" maxOccurs="unbounded">' +
    '<xs:element ref="r" minOccurs="0"/><xs:any namespace="urn:y  urn:z" processContents="lax"/>' +
    '</xs:sequence><xs:attribute name="a" form="qualified" ' +
    'use="required"><xs:simpleType><xs:restriction base="xs:string"><xs:maxLength value=" 5 " fixed="true"/>' +
    '<xs:enumeration value="x"/></xs:restriction></xs:simpleType></xs:attribute><xs:anyAttribute ' +
    'namespace="##any" processContents="skip"/></xs:complexType></xs:element>' +
    '<xs:group name="g"><xs:annotation/><xs:sequence><xs:element name="x"/></xs:sequence></xs:group>' +
    '<xs:simpleType name="u" final="#all"><xs:union memberTypes="xs:int  xs:date"><xs:simpleType>' +
    '<xs:list itemType="xs:token"/></xs:simpleType></xs:union></xs:simpleType>' +
    '<xs:element name="m" fixed="x"><xs:complexType mixed="true"><xs:sequence minOccurs="0">' +
    '<xs:element name="a"/></xs:sequence></xs:complexType></xs:element>' +
    '<xs:attribute name="d" type="xs:decimal" fixed="1.0"/><xs:element name="u"><xs:complexType>' +
    '<xs:attribute ref="d" fixed="1"/><xs:attribute name="w" type="xs:int" default="7"/></xs:complexType>' +
    '</xs:element>' +
    '<xs:element name="o" default="x"><xs:complexType mixed="true"><xs:sequence minOccurs="0" maxOccurs="2">' +
    '<xs:any minOccurs="2" maxOccurs="3" processContents="lax"/></xs:sequence></xs:complexType></xs:element>' +
    '<xs:attribute name="dt" type="xs:date" fixed="2000-01-01+01:00"/><xs:element name="v"><xs:complexType>' +
    '<xs:attribute ref="dt" fixed="1999-12-31Z"/></xs:complexType></xs:element>' +
    '<xs:complexType name="t" block="extension restriction" final="#all"><xs:simpleContent>' +
    '<xs:extension base="xs:int"><xs:attribute name="b" type="xs:int" default="1"/></xs:extension>' +
    '</xs:simpleContent></xs:complexType>', ' xmlns:t="urn:x" elementFormDefault="qualified" ' +
    'blockDefault="substitution" finalDefault="list union" xml:lang="en" version="1.0"');
  S := nil;
  try
    S := LandrixXmlXsdLoadSchema(FileName);
    Check(S.FindElement('', 'r') <> nil, 'valid forms load');
  finally
    S.Free;
    DeleteFile(FileName);
  end;
  FileName := TempSchema('<xs:complexType name="fe" final="restriction"><xs:sequence><xs:element name="x"/>' +
    '</xs:sequence></xs:complexType><xs:complexType name="fe2"><xs:complexContent>' +
    '<xs:extension base="fe"><xs:sequence><xs:element name="y"/></xs:sequence></xs:extension>' +
    '</xs:complexContent></xs:complexType><xs:complexType name="fr" final="extension"/>' +
    '<xs:complexType name="fr2"><xs:complexContent><xs:restriction base="fr"/></xs:complexContent>' +
    '</xs:complexType><xs:complexType name="fd" final=""/><xs:complexType name="fd2">' +
    '<xs:complexContent><xs:extension base="fd"/></xs:complexContent></xs:complexType>' +
    '<xs:simpleType name="sl" final="restriction"><xs:restriction base="xs:int"/></xs:simpleType>' +
    '<xs:simpleType name="sl2"><xs:list itemType="sl"/></xs:simpleType><xs:simpleType name="su">' +
    '<xs:union memberTypes="xs:int xs:date"/></xs:simpleType><xs:complexType name="sc">' +
    '<xs:simpleContent><xs:extension base="xs:decimal"><xs:attribute name="a" type="su"/>' +
    '<xs:attribute name="f" type="xs:decimal" fixed="1.0"/>' +
    '<xs:attribute name="r" type="xs:int" use="required"/>' +
    '<xs:attribute name="o" type="xs:anySimpleType"/><xs:attribute name="p"/></xs:extension>' +
    '</xs:simpleContent></xs:complexType><xs:complexType name="sc2"><xs:simpleContent>' +
    '<xs:restriction base="sc"><xs:simpleType><xs:restriction base="xs:integer"/></xs:simpleType>' +
    '<xs:maxInclusive value="5"/><xs:attribute name="a" type="xs:short"/>' +
    '<xs:attribute name="f" type="xs:decimal" fixed="1"/>' +
    '<xs:attribute name="r" type="xs:byte" use="required"/><xs:attribute name="o" type="sl2"/>' +
    '<xs:attribute name="p" use="prohibited"/></xs:restriction></xs:simpleContent></xs:complexType>' +
    '<xs:complexType name="mx" mixed="true"><xs:sequence minOccurs="0"><xs:element name="x"/>' +
    '</xs:sequence><xs:anyAttribute namespace="##any" processContents="lax"/></xs:complexType>' +
    '<xs:complexType name="mx2"><xs:simpleContent><xs:restriction base="mx"><xs:simpleType>' +
    '<xs:restriction base="xs:string"/></xs:simpleType></xs:restriction></xs:simpleContent>' +
    '</xs:complexType><xs:complexType name="mx3" mixed="true"><xs:complexContent>' +
    '<xs:extension base="mx"><xs:sequence><xs:element name="y"/></xs:sequence></xs:extension>' +
    '</xs:complexContent></xs:complexType><xs:complexType name="mx4"><xs:complexContent>' +
    '<xs:extension base="mx"><xs:attribute name="b"/></xs:extension></xs:complexContent>' +
    '</xs:complexType><xs:complexType name="mx5"><xs:complexContent><xs:restriction base="mx">' +
    '<xs:sequence><xs:element name="x"/></xs:sequence><xs:attribute name="n" type="xs:ID"/>' +
    '<xs:anyAttribute namespace="##other" processContents="strict"/></xs:restriction>' +
    '</xs:complexContent></xs:complexType><xs:complexType name="em"/>' +
    '<xs:complexType name="em2" mixed="true"><xs:complexContent><xs:extension base="em"/>' +
    '</xs:complexContent></xs:complexType><xs:complexType name="el"><xs:sequence>' +
    '<xs:element name="x"/></xs:sequence></xs:complexType><xs:complexType name="el2">' +
    '<xs:complexContent><xs:extension base="el"><xs:sequence/></xs:extension></xs:complexContent>' +
    '</xs:complexType><xs:complexType name="ss"><xs:simpleContent><xs:extension base="xs:int"/>' +
    '</xs:simpleContent></xs:complexType><xs:complexType name="ss2"><xs:complexContent>' +
    '<xs:extension base="ss"><xs:attribute name="b"/></xs:extension></xs:complexContent>' +
    '</xs:complexType><xs:complexType name="z1"><xs:simpleContent><xs:extension base="xs:string"/>' +
    '</xs:simpleContent></xs:complexType><xs:complexType name="z2"><xs:complexContent>' +
    '<xs:extension base="z1"><xs:sequence minOccurs="0" maxOccurs="0"><xs:element name="x"/>' +
    '</xs:sequence></xs:extension></xs:complexContent></xs:complexType><xs:simpleType name="zs">' +
    '<xs:union memberTypes="xs:string xs:anyURI"/></xs:simpleType><xs:complexType name="zb">' +
    '<xs:attribute name="a" type="zs" fixed="urn:x"/></xs:complexType><xs:complexType name="zd">' +
    '<xs:complexContent><xs:restriction base="zb">' +
    '<xs:attribute name="a" type="xs:anyURI" fixed="urn:x"/></xs:restriction></xs:complexContent>' +
    '</xs:complexType><xs:simpleType name="zu" final="restriction">' +
    '<xs:union memberTypes="xs:int xs:string"/></xs:simpleType><xs:complexType name="za">' +
    '<xs:simpleContent><xs:extension base="zu"/></xs:simpleContent></xs:complexType>' +
    '<xs:complexType name="zr"><xs:simpleContent><xs:restriction base="za"/></xs:simpleContent>' +
    '</xs:complexType><xs:complexType name="zr2"><xs:simpleContent><xs:restriction base="zr">' +
    '<xs:simpleType><xs:restriction base="xs:int"/></xs:simpleType></xs:restriction>' +
    '</xs:simpleContent></xs:complexType><xs:simpleType name="zl1"><xs:list itemType="xs:string"/>' +
    '</xs:simpleType><xs:simpleType name="zl2"><xs:list itemType="xs:anyURI"/></xs:simpleType>' +
    '<xs:simpleType name="zlu"><xs:union memberTypes="zl1 zl2"/></xs:simpleType>' +
    '<xs:complexType name="zlb"><xs:attribute name="a" type="zlu" fixed="urn:x urn:y"/>' +
    '</xs:complexType><xs:complexType name="zld"><xs:complexContent><xs:restriction base="zlb">' +
    '<xs:attribute name="a" type="zl2" fixed="urn:x urn:y"/></xs:restriction></xs:complexContent>' +
    '</xs:complexType><xs:simpleType name="zi" final=""><xs:union memberTypes="xs:int xs:string"/>' +
    '</xs:simpleType><xs:simpleType name="zm1"><xs:list itemType="zi"/></xs:simpleType>' +
    '<xs:simpleType name="zm2"><xs:list itemType="xs:int"/></xs:simpleType>' +
    '<xs:simpleType name="zmu"><xs:union memberTypes="zm1 zm2"/></xs:simpleType>' +
    '<xs:complexType name="zmb"><xs:attribute name="a" type="zmu" fixed="1 2"/></xs:complexType>' +
    '<xs:complexType name="zmd"><xs:complexContent><xs:restriction base="zmb">' +
    '<xs:attribute name="a" type="zm2" fixed="1 2"/></xs:restriction></xs:complexContent>' +
    '</xs:complexType><xs:complexType name="zc" mixed="true"/><xs:complexType name="zc2">' +
    '<xs:complexContent><xs:extension base="zc"><xs:choice minOccurs="00"/></xs:extension>' +
    '</xs:complexContent></xs:complexType><xs:complexType name="zx" mixed="true"/>' +
    '<xs:complexType name="zx2"><xs:complexContent><xs:extension base="zx"/></xs:complexContent>' +
    '</xs:complexType><xs:complexType name="zx3" mixed="true"><xs:complexContent>' +
    '<xs:restriction base="zx2"/></xs:complexContent></xs:complexType><xs:element name="r"/>',
    ' finalDefault="list"');
  S := nil;
  try
    S := LandrixXmlXsdLoadSchema(FileName);
    Check(S.FindElement('', 'r') <> nil, 'valid derivations load');
  finally
    S.Free;
    DeleteFile(FileName);
  end;
end;

procedure Register;
begin
  RegisterTest('XsdValidator.Basics', TestBasics);
  RegisterTest('XsdValidator.Derivation', TestDerivation);
  RegisterTest('XsdValidator.Wildcards', TestWildcards);
  RegisterTest('XsdValidator.Identity', TestIdentity);
  RegisterTest('XsdValidator.Occurrence', TestOccurrence);
  RegisterTest('XsdValidator.Values', TestValues);
  RegisterTest('XsdValidator.EdgeCases', TestEdgeCases);
  RegisterTest('XsdValidator.KeyRefOutOfScope', TestKeyRefOutOfScope);
  RegisterTest('XsdValidator.LoadErrors', TestLoadErrors);
  RegisterTest('XsdValidator.LargeOccurs', TestLargeOccurs);
  RegisterTest('XsdValidator.Unresolved', TestUnresolved);
  RegisterTest('XsdValidator.SchemaRules', TestSchemaRules);
  {$IFDEF MSWINDOWS}
  RegisterTest('XsdValidator.FileCase', TestFileCase);
  {$ENDIF}
  RegisterTest('XsdValidator.Api', TestApi);
end;

end.
