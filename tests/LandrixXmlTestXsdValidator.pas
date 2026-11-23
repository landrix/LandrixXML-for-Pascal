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
  Contnrs,
  LandrixXmlBase,
  LandrixXmlReader,
  LandrixXmlDom,
  LandrixXmlXsdTypes,
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
        'f': Result[N] := #12;
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
  Title, Expected, Got, GotPlain, Report: string;
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
    GotPlain := ErrorLines(V, False);
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
    { the DOM path too: the same errors as the reader (for the JDK
      exception cases, whose expected text is only a prefix) }
    if Ok and JdkException then
      Ok := ErrorLines(V, False) = GotPlain
    else if Ok then
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
  CheckLoadError('<xs:simpleType name="l"><xs:list itemType="xs:int"/></xs:simpleType>' +
    '<xs:simpleType name="ll"><xs:list itemType="l"/></xs:simpleType>', xecSchema, 'a list of lists');
  CheckLoadError('<xs:element name="r"><xs:unique name="u"><xs:selector xpath="a/@b/c"/>' +
    '<xs:field xpath="."/></xs:unique></xs:element>', xecUnsupported, 'an attribute step inside a selector');
  CheckLoadError('<xs:element name="h" substitutionGroup="r"/><xs:element name="r" substitutionGroup="h"/>',
    xecSchema, 'circular substitution group');
  CheckLoadError('<xs:element name="r" type="xs:error"/>', xecSchema, 'no built-in type');
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
{ The derivation data and checks of the schema components (used for
  xsi:type), on the schema of the edge case xsi-type. }
procedure TestTypeDerivation;
var
  S: TLandrixXmlXsdSchemaSet;
  B, E, R, BX, SC: TLandrixXmlXsdComplexType;
  Dec, Int, Str, AnySimple: TLandrixXmlXsdSimpleType;
  Decl: TLandrixXmlXsdElementDecl;
  NS: TLandrixXmlUtf8;
begin
  S := LandrixXmlXsdLoadSchema(CaseFolder('edge' + PathDelim + 'xsi-type') + 'main.xsd');
  try
    NS := U('urn:t');
    B := S.FindComplexType(NS, U('B'));
    E := S.FindComplexType(NS, U('E'));
    R := S.FindComplexType(NS, U('R'));
    BX := S.FindComplexType(NS, U('BX'));
    SC := S.FindComplexType(NS, U('SC'));
    Dec := LandrixXmlXsdBuiltinType('decimal');
    Int := LandrixXmlXsdBuiltinType('int');
    Str := LandrixXmlXsdBuiltinType('string');
    AnySimple := LandrixXmlXsdBuiltinType('anySimpleType');
    Check(BX.Block = [xdExtension], 'block of a complex type');
    Check(B.Block = [], 'no block');
    Check(S.FindComplexType(NS, U('EE')).Final = [xdRestriction, xdExtension], 'final #all of a complex type');
    Check(B.Final = [], 'no final');
    Decl := S.FindElement(NS, U('Root'));
    Check(not Decl.Nillable and (Decl.Block = []), 'element without nillable and block');
    Check(S.TypeDerivationOk(nil, E, nil, B, []), 'extension');
    Check(not S.TypeDerivationOk(nil, E, nil, B, [xdExtension]), 'extension blocked');
    Check(S.TypeDerivationOk(nil, R, nil, B, [xdExtension]), 'restriction');
    Check(not S.TypeDerivationOk(nil, B, nil, E, []), 'base from derived');
    Check(S.TypeDerivationOk(nil, B, nil, S.AnyType, []), 'complex from anyType');
    Check(not S.TypeDerivationOk(nil, S.AnyType, nil, B, []), 'anyType from complex');
    Check(S.TypeDerivationOk(nil, SC, Dec, nil, []), 'simple content from its simple base');
    Check(S.TypeDerivationOk(Int, nil, Dec, nil, []), 'int from decimal');
    Check(not S.TypeDerivationOk(Int, nil, Dec, nil, [xdRestriction]), 'restriction blocked');
    Check(not S.TypeDerivationOk(Str, nil, Dec, nil, []), 'string from decimal');
    Check(S.TypeDerivationOk(Int, nil, nil, S.AnyType, []), 'simple from anyType');
    Check(not S.TypeDerivationOk(Int, nil, nil, B, []), 'simple from complex');
    Check(S.TypeDerivationOk(AnySimple, nil, nil, S.AnyType, []), 'anySimpleType from anyType');
    try
      S.TypeDerivationOk(Int, B, Dec, nil, []);
      FailNotRaised('ELandrixXmlError for two derived types');
    except
      on Ex: ELandrixXmlError do
        CheckEquals(Ord(xecInvalidArgument), Ord(Ex.Code), 'two derived types');
    end;
  finally
    S.Free;
  end;
end;

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

{ Composite key tuples are compared field by field: a TAB (or any other
  separator) inside a field value must not make two tuples equal. }
procedure TestCompositeKeySeparator;
var
  FileName: string;
  S: TLandrixXmlXsdSchemaSet;
  V: TLandrixXmlXsdValidator;
  Reader: TLandrixXmlReader;
begin
  FileName := TempSchema('<xs:element name="r"><xs:complexType><xs:sequence>' +
    '<xs:element name="a" minOccurs="0" maxOccurs="unbounded"><xs:complexType>' +
    '<xs:attribute name="x" type="xs:string"/><xs:attribute name="y" type="xs:string"/>' +
    '</xs:complexType></xs:element>' +
    '<xs:element name="b" minOccurs="0" maxOccurs="unbounded"><xs:complexType>' +
    '<xs:attribute name="x" type="xs:string"/><xs:attribute name="y" type="xs:string"/>' +
    '</xs:complexType></xs:element></xs:sequence></xs:complexType>' +
    '<xs:key name="k"><xs:selector xpath="a"/><xs:field xpath="@x"/><xs:field xpath="@y"/></xs:key>' +
    '<xs:keyref name="ref" refer="k"><xs:selector xpath="b"/><xs:field xpath="@x"/><xs:field xpath="@y"/>' +
    '</xs:keyref></xs:element>');
  S := LandrixXmlXsdLoadSchema(FileName);
  V := TLandrixXmlXsdValidator.Create(S);
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromUtf8(U('<r><a x="a&#9;1:b" y="c"/><b x="a" y="b&#9;1:c"/></r>'));
    Check(not V.ValidateReader(Reader), 'keyref to a tuple that only matches when joined');
    CheckEqualsStr('cvc-identity-constraint.4.3', V.Errors[0].Code, 'keyref code');
    Reader.LoadFromUtf8(U('<r><a x="a&#9;1:b" y="c"/><a x="a" y="b&#9;1:c"/></r>'));
    Check(V.ValidateReader(Reader), 'two different tuples are no duplicate');
    Reader.LoadFromUtf8(U('<r><a x="a&#9;1:b" y="c"/><a x="a&#9;1:b" y="c"/></r>'));
    Check(not V.ValidateReader(Reader), 'real duplicate');
    CheckEqualsStr('cvc-identity-constraint.4.2.2', V.Errors[0].Code, 'duplicate code');
  finally
    Reader.Free;
    V.Free;
    S.Free;
    DeleteFile(FileName);
  end;
end;

{ Sibling positions in error paths stay right once an element has more
  distinct child names than the linear search handles (hash table), also
  for the next element that reuses the frame. }
procedure TestManyChildNames;
var
  FileName: string;
  S: TLandrixXmlXsdSchemaSet;
  V: TLandrixXmlXsdValidator;
  Reader: TLandrixXmlReader;
  Xml: TLandrixXmlUtf8;
  I, Round: Integer;
begin
  FileName := TempSchema('<xs:element name="r"><xs:complexType><xs:sequence>' +
    '<xs:element name="g" maxOccurs="unbounded"><xs:complexType><xs:sequence>' +
    '<xs:any processContents="lax" minOccurs="0" maxOccurs="unbounded"/></xs:sequence></xs:complexType>' +
    '</xs:element></xs:sequence></xs:complexType></xs:element><xs:element name="bad" type="xs:int"/>');
  S := LandrixXmlXsdLoadSchema(FileName);
  V := TLandrixXmlXsdValidator.Create(S);
  Reader := TLandrixXmlReader.Create;
  try
    Xml := '<r>';
    for Round := 1 to 2 do
    begin
      Xml := Xml + '<g>';
      for I := 0 to 99 do
        Xml := Xml + '<e' + LandrixXmlStringToUtf8(IntToStr(I)) + '/><bad>1</bad>';
      Xml := Xml + '<bad>x</bad><e7/><bad>y</bad></g>';
    end;
    Xml := Xml + '</r>';
    Reader.LoadFromUtf8(Xml);
    Check(not V.ValidateReader(Reader), 'invalid');
    CheckEquals(8, V.ErrorCount, 'two errors per bad value');
    CheckEqualsUtf8(U('/r/g[1]/bad[101]'), V.Errors[0].Path, 'first bad value');
    CheckEqualsUtf8(U('/r/g[1]/bad[102]'), V.Errors[2].Path, 'second bad value');
    CheckEqualsUtf8(U('/r/g[2]/bad[101]'), V.Errors[4].Path, 'next element');
    CheckEqualsUtf8(U('/r/g[2]/bad[102]'), V.Errors[6].Path, 'next element, second value');
  finally
    Reader.Free;
    V.Free;
    S.Free;
    DeleteFile(FileName);
  end;
end;

{ a document whose ENTITY e is declared through a chain of Levels
  parameter entities (the references inside the entity values are
  character references: a literal "%" there is not well-formed in the
  internal subset) }
function EntityChain(Levels: Integer): TLandrixXmlUtf8;
var
  I: Integer;
  S: string;
begin
  S := '<!DOCTYPE r [<!ENTITY % p1 "<!ENTITY e SYSTEM ''e.gif'' NDATA gif>">';
  for I := 2 to Levels do
    S := S + '<!ENTITY % p' + IntToStr(I) + ' "&#37;p' + IntToStr(I - 1) + ';">';
  S := S + '%p' + IntToStr(Levels) + ';]><r><a>1</a><e>e</e></r>';
  Result := U(S);
end;

procedure TestApi;
var
  FileName: string;
  S: TLandrixXmlXsdSchemaSet;
  V: TLandrixXmlXsdValidator;
  Reader: TLandrixXmlReader;
  I: Integer;
  Xml: TLandrixXmlUtf8;
  Doc: TLandrixXmlDocument;
begin
  FileName := TempSchema('<xs:element name="r"><xs:complexType><xs:sequence>' +
    '<xs:element name="a" type="xs:int" maxOccurs="unbounded"/><xs:element name="e" type="xs:ENTITY" minOccurs="0"/>' +
    '</xs:sequence></xs:complexType></xs:element>');
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
    { an ENTITY value names an unparsed entity of the internal subset,
      also when the document is loaded first }
    V.MaxErrors := 0;
    Xml := '<r xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xs="http://www.w3.org/2001/XMLSchema">' +
      '<a>1</a><e>e</e></r>';
    Reader.LoadFromUtf8(Xml);
    Check(not V.ValidateReader(Reader), 'ENTITY');
    Check(V.ErrorCount > 0, 'an error for ENTITY');
    CheckEqualsStr('UndeclaredEntity', V.Errors[0].Code, 'no unparsed entity e');
    for I := 0 to V.ErrorCount - 1 do
      Check(V.Errors[I].Code <> '', 'every error has a code');
    Xml := '<!DOCTYPE r [<!ENTITY e SYSTEM "e.gif" NDATA gif><!NOTATION gif SYSTEM "v">]>' + Xml;
    Reader.LoadFromUtf8(Xml);
    Check(V.ValidateReader(Reader), 'unparsed entity e');
    Doc := TLandrixXmlDocument.Create;
    try
      Doc.LoadFromUtf8(Xml);
      Check(V.ValidateDocument(Doc), 'unparsed entity e in a document');
    finally
      Doc.Free;
    end;
    { a parameter entity that refers to itself is not well-formed; one that
      expands exponentially stops at the limit; both only matter when an
      ENTITY value is checked }
    Reader.LoadFromUtf8('<!DOCTYPE r [<!ENTITY % p "%p;%p;"> %p;]><r><a>1</a></r>');
    Check(V.ValidateReader(Reader), 'no ENTITY value');
    Reader.LoadFromUtf8('<!DOCTYPE r [<!ENTITY % p "%p;%p;"> %p;]><r><a>1</a><e>e</e></r>');
    try
      V.ValidateReader(Reader);
      FailNotRaised('recursive parameter entity');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecSyntax), Ord(E.Code), 'recursive parameter entity');
    end;
    Doc := TLandrixXmlDocument.Create;
    try
      Doc.LoadFromUtf8('<!DOCTYPE r [<!ENTITY % p "%p;%p;"> %p;]><r><a>1</a><e>e</e></r>');
      try
        V.ValidateDocument(Doc);
        FailNotRaised('recursive parameter entity in a document');
      except
        on E: ELandrixXmlError do
          CheckEquals(Ord(xecSyntax), Ord(E.Code), 'recursive parameter entity in a document');
      end;
    finally
      Doc.Free;
    end;
    Reader.LoadFromUtf8('<!DOCTYPE r [<!ENTITY % a "<!ENTITY e SYSTEM ''e.gif'' NDATA gif>">' +
      '<!ENTITY % b "%a;%a;%a;%a;%a;%a;%a;%a;%a;%a;"><!ENTITY % c "%b;%b;%b;%b;%b;%b;%b;%b;%b;%b;">' +
      '<!ENTITY % d "%c;%c;%c;%c;%c;%c;%c;%c;%c;%c;"><!ENTITY % f "%d;%d;%d;%d;%d;%d;%d;%d;%d;%d;">' +
      '<!ENTITY % g "%f;%f;%f;%f;%f;%f;%f;%f;%f;%f;"><!ENTITY % h "%g;%g;%g;%g;%g;%g;%g;%g;%g;%g;">' +
      '<!ENTITY % i "%h;%h;%h;%h;%h;%h;%h;%h;%h;%h;"><!ENTITY % j "%i;%i;%i;%i;%i;%i;%i;%i;%i;%i;">' +
      '<!ENTITY % k "%j;%j;%j;%j;%j;%j;%j;%j;%j;%j;"> %k;]><r><a>1</a><e>e</e></r>');
    try
      V.ValidateReader(Reader);
      FailNotRaised('exponential parameter entities');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecLimit), Ord(E.Code), 'exponential parameter entities');
    end;
    Reader.LoadFromUtf8('<!DOCTYPE r [<!ENTITY % a "<!ENTITY e SYSTEM ''e.gif'' NDATA gif>">' +
      '<!ENTITY % b "%a;%a;"> %b;]><r><a>1</a><e>e</e></r>');
    Check(V.ValidateReader(Reader), 'nested parameter entities');
    { a linear chain: 64 levels are read, 65 are xecLimit }
    Reader.LoadFromUtf8(EntityChain(64));
    Check(V.ValidateReader(Reader), 'parameter entities 64 levels deep');
    Reader.LoadFromUtf8(EntityChain(65));
    try
      V.ValidateReader(Reader);
      FailNotRaised('parameter entities 65 levels deep');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecLimit), Ord(E.Code), 'parameter entities 65 levels deep');
    end;
    { after a parameter entity that is not read, later entity declarations
      do not count (XML 1.0, 5.1), unless the document is standalone }
    Xml := '<!DOCTYPE r [<!ENTITY % x SYSTEM "x.ent"> %x; <!ENTITY e SYSTEM "e.gif" NDATA gif>' +
      '<!NOTATION gif SYSTEM "v">]><r><a>1</a><e>e</e></r>';
    Reader.LoadFromUtf8(Xml);
    Check(not V.ValidateReader(Reader), 'declaration after an unread parameter entity');
    CheckEqualsStr('UndeclaredEntity', V.Errors[0].Code, 'e is not known');
    Reader.LoadFromUtf8('<!DOCTYPE r [%y; <!ENTITY e SYSTEM "e.gif" NDATA gif>]><r><a>1</a><e>e</e></r>');
    Check(not V.ValidateReader(Reader), 'declaration after an undeclared parameter entity');
    Xml := '<?xml version="1.0" standalone="yes"?>' + Xml;
    Reader.LoadFromUtf8(Xml);
    Check(V.ValidateReader(Reader), 'standalone: the declaration counts');
    Doc := TLandrixXmlDocument.Create;
    try
      Doc.LoadFromUtf8(Xml);
      Check(V.ValidateDocument(Doc), 'standalone document');
    finally
      Doc.Free;
    end;
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

{ Limits of the content models from the review: a variable range beyond
  High(Integer) stays a range for Unique Particle Attribution; a repeated
  group with a large minOccurs around a repeated element stops at the
  limit instead of taking cubic time; a model too costly for the UPA
  automaton is taken as unambiguous (README, Limitations). }
procedure TestContentLimits;
var
  FileName, Body, Cham, ChamB: string;
  S: TLandrixXmlXsdSchemaSet;
  V: TLandrixXmlXsdValidator;
  Reader: TLandrixXmlReader;
  I: Integer;
  Raised: Boolean;

  function Group(Count: Integer): string;
  begin
    Result := '<xs:element name="r"><xs:complexType><xs:sequence minOccurs="' + IntToStr(Count) +
      '" maxOccurs="' + IntToStr(Count) + '"><xs:element name="a" maxOccurs="unbounded"/>' +
      '</xs:sequence></xs:complexType></xs:element>';
  end;

  function IsValid(const SchemaFile: string; const Xml: string): Boolean;
  var
    Schemas: TLandrixXmlXsdSchemaSet;
    Validator: TLandrixXmlXsdValidator;
    R: TLandrixXmlReader;
  begin
    Schemas := LandrixXmlXsdLoadSchema(SchemaFile);
    Validator := TLandrixXmlXsdValidator.Create(Schemas);
    R := TLandrixXmlReader.Create;
    try
      R.LoadFromUtf8(U(Xml));
      Result := Validator.ValidateReader(R);
    finally
      R.Free;
      Validator.Free;
      Schemas.Free;
    end;
  end;

  function Children(Count: Integer): TLandrixXmlUtf8;
  var
    J: Integer;
  begin
    Result := '<r>';
    for J := 1 to Count do
      Result := Result + '<a/>';
    Result := Result + '</r>';
  end;

begin
  { the range of the derived content, 2^64, is no longer 0 after an Int64
    overflow (Xerces stops earlier at its size limit) }
  CheckLoadError('<xs:complexType name="b"><xs:sequence><xs:any minOccurs="0" maxOccurs="1"/></xs:sequence>' +
    '</xs:complexType><xs:complexType name="d"><xs:complexContent><xs:restriction base="b">' +
    '<xs:sequence minOccurs="0" maxOccurs="2097152"><xs:sequence minOccurs="0" maxOccurs="2097152">' +
    '<xs:element name="e" minOccurs="0" maxOccurs="4194304"/></xs:sequence></xs:sequence>' +
    '</xs:restriction></xs:complexContent></xs:complexType><xs:element name="r"/>', xecSchema,
    'a range beyond Int64 below a wildcard');
  CheckLoadError('<xs:element name="r"><xs:complexType><xs:sequence>' +
    '<xs:element name="a" minOccurs="2147483647" maxOccurs="2147483648"/><xs:element name="a"/>' +
    '</xs:sequence></xs:complexType></xs:element>', xecSchema, 'ambiguous range at High(Integer)');
  CheckLoadError('<xs:element name="r"><xs:complexType><xs:sequence>' +
    '<xs:element name="a" minOccurs="12678967543233" maxOccurs="12678967543234"/><xs:element name="a"/>' +
    '</xs:sequence></xs:complexType></xs:element>', xecSchema, 'ambiguous range beyond Integer');
  { a group taken 20 times is fine; 2000 times stops at the limit }
  FileName := TempSchema(Group(20));
  S := LandrixXmlXsdLoadSchema(FileName);
  V := TLandrixXmlXsdValidator.Create(S);
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromUtf8(Children(20));
    Check(V.ValidateReader(Reader), 'group of 20');
  finally
    Reader.Free;
    V.Free;
    S.Free;
    DeleteFile(FileName);
  end;
  FileName := TempSchema(Group(2000));
  S := LandrixXmlXsdLoadSchema(FileName);
  V := TLandrixXmlXsdValidator.Create(S);
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromUtf8(Children(2000));
    Raised := False;
    try
      V.ValidateReader(Reader);
    except
      on E: ELandrixXmlError do
      begin
        Raised := True;
        CheckEquals(Ord(xecLimit), Ord(E.Code), 'group of 2000: ' + E.Message);
      end;
    end;
    Check(Raised, 'group of 2000 stops at the limit');
  finally
    Reader.Free;
    V.Free;
    S.Free;
    DeleteFile(FileName);
  end;
  { an included document with targetNamespace="" is a chameleon, as for
    Xerces (README, Xerces deviations) }
  Body := ExtractFilePath(ParamStr(0)) + 'xsdtest-empty-tns.xsd';
  WriteTestFile(Body, '<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="">' +
    '<xs:element name="e"/></xs:schema>');
  FileName := TempSchema('<xs:include schemaLocation="xsdtest-empty-tns.xsd"/>', ' targetNamespace="urn:x"');
  S := nil;
  try
    S := LandrixXmlXsdLoadSchema(FileName);
    Check(S.FindElement('urn:x', 'e') <> nil, 'chameleon with targetNamespace=""');
  finally
    S.Free;
    DeleteFile(FileName);
    DeleteFile(Body);
  end;
  { a repeated namespace in an extension wildcard keeps urn:b of the base }
  FileName := TempSchema('<xs:complexType name="b"><xs:anyAttribute namespace="urn:a urn:b" ' +
    'processContents="skip"/></xs:complexType><xs:complexType name="d"><xs:complexContent>' +
    '<xs:extension base="b"><xs:anyAttribute namespace="urn:a urn:a" processContents="skip"/>' +
    '</xs:extension></xs:complexContent></xs:complexType><xs:element name="r" type="d"/>');
  try
    Check(IsValid(FileName, '<r xmlns:b="urn:b" b:x="1"/>'), 'wildcard union keeps urn:b');
  finally
    DeleteFile(FileName);
  end;
  { one chameleon attribute group in two namespaces: two attribute uses }
  { the names before the try: a string expression in the finally part
    leaks a temporary with FPC 3.3.1 }
  Body := ExtractFilePath(ParamStr(0));
  Cham := Body + 'xsdtest-cham.xsd';
  ChamB := Body + 'xsdtest-cham-b.xsd';
  WriteTestFile(Cham, '<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">' +
    '<xs:attributeGroup name="g"><xs:attribute name="x" form="qualified" use="required"/>' +
    '</xs:attributeGroup></xs:schema>');
  WriteTestFile(ChamB, '<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" ' +
    'targetNamespace="urn:b"><xs:include schemaLocation="xsdtest-cham.xsd"/></xs:schema>');
  FileName := TempSchema('<xs:include schemaLocation="xsdtest-cham.xsd"/><xs:import namespace="urn:b" ' +
    'schemaLocation="xsdtest-cham-b.xsd"/><xs:element name="r"><xs:complexType><xs:attributeGroup ref="a:g"/>' +
    '<xs:attributeGroup ref="b:g"/><xs:attributeGroup ref="a:g"/></xs:complexType></xs:element>',
    ' targetNamespace="urn:a" xmlns:a="urn:a" xmlns:b="urn:b"');
  try
    Check(IsValid(FileName, '<a:r xmlns:a="urn:a" xmlns:b="urn:b" a:x="1" b:x="2"/>'), 'both chameleon uses');
    Check(not IsValid(FileName, '<a:r xmlns:a="urn:a" xmlns:b="urn:b" a:x="1"/>'), 'b:x is required');
  finally
    DeleteFile(FileName);
    DeleteFile(Cham);
    DeleteFile(ChamB);
  end;
  { 3000 optional elements and the ambiguous a?, a: too costly for the
    check, so taken as unambiguous (with 10 the ambiguity is reported) }
  Body := '<xs:element name="r"><xs:complexType><xs:sequence>';
  for I := 1 to 10 do
    Body := Body + '<xs:element name="e' + IntToStr(I) + '" minOccurs="0"/>';
  CheckLoadError(Body + '<xs:element name="a" minOccurs="0"/><xs:element name="a"/></xs:sequence>' +
    '</xs:complexType></xs:element>', xecSchema, 'a?, a after 10 optional elements');
  Body := '<xs:element name="r"><xs:complexType><xs:sequence>';
  for I := 1 to 3000 do
    Body := Body + '<xs:element name="e' + IntToStr(I) + '" minOccurs="0"/>';
  Body := Body + '<xs:element name="a" minOccurs="0"/><xs:element name="a"/></xs:sequence>' +
    '</xs:complexType></xs:element>';
  FileName := TempSchema(Body);
  S := nil;
  try
    S := LandrixXmlXsdLoadSchema(FileName);
    Check(S <> nil, 'large model loaded');
  finally
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

{$IFDEF LINUX}
{ two files whose names differ only in case are two documents on Linux,
  also in the list of files (in a folder of /tmp per process: the build
  folder may be a case-insensitive mount, such as a Windows drive under
  WSL) }
procedure TestFileCaseLinux;
var
  Dir, A, B, C: string;
  S: TLandrixXmlXsdSchemaSet;
begin
  Dir := '/tmp/landrixxml-case-' + IntToStr(GetProcessID) + '/';
  A := Dir + 'main.xsd';
  B := Dir + 'x.xsd';
  C := Dir + 'X.xsd';
  S := nil;
  try
    ForceDirectories(Dir);
    WriteTestFile(A, '<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">' +
      '<xs:include schemaLocation="x.xsd"/><xs:include schemaLocation="X.xsd"/></xs:schema>');
    WriteTestFile(B, '<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"><xs:element name="b"/></xs:schema>');
    WriteTestFile(C, '<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"><xs:element name="c"/></xs:schema>');
    S := LandrixXmlXsdLoadSchema(A);
    Check(S.FindElement('', 'c') <> nil, 'element of the second file');
    CheckEquals(3, Integer(S.Files.Count), 'three files');
  finally
    S.Free;
    DeleteFile(A);
    DeleteFile(B);
    DeleteFile(C);
    RemoveDir(Dir);
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

function SplitTabs(const Line: string): TStringList;
var
  P: Integer;
  Rest: string;
begin
  Result := TStringList.Create;
  Rest := Line;
  P := Pos(#9, Rest);
  while P > 0 do
  begin
    Result.Add(Copy(Rest, 1, P - 1));
    Rest := Copy(Rest, P + 1, MaxInt);
    P := Pos(#9, Rest);
  end;
  Result.Add(Rest);
end;

{ A type of a loaded schema document of the XML Schema namespace needs an
  import in every document that refers to it (Xerces: src-resolve.4.2 in
  the included document c, which does not import the namespace itself) }
procedure TestXsNamespaceImport;
const
  XsNs = 'http://www.w3.org/2001/XMLSchema';
var
  Dir, A, B, C: string;
  S: TLandrixXmlXsdSchemaSet;
begin
  Dir := ExtractFilePath(ParamStr(0));
  A := Dir + 'xsns-a.xsd';
  B := Dir + 'xsns-b.xsd';
  C := Dir + 'xsns-c.xsd';
  WriteTestFile(B, '<xs:schema xmlns:xs="' + XsNs + '" targetNamespace="' + XsNs + '">' +
    '<xs:simpleType name="myT"><xs:restriction base="xs:string"/></xs:simpleType></xs:schema>');
  WriteTestFile(C, '<xs:schema xmlns:xs="' + XsNs + '"><xs:element name="c" type="xs:myT"/></xs:schema>');
  WriteTestFile(A, '<xs:schema xmlns:xs="' + XsNs + '"><xs:import namespace="' + XsNs +
    '" schemaLocation="xsns-b.xsd"/><xs:include schemaLocation="xsns-c.xsd"/>' +
    '<xs:element name="r" type="xs:myT"/></xs:schema>');
  S := nil;
  try
    try
      S := LandrixXmlXsdLoadSchema(A);
      S.Free;
      S := nil;
      FailNotRaised('src-resolve.4.2 for xs:myT without an import');
    except
      on E: ELandrixXmlXsdSchemaError do
      begin
        CheckEqualsStr('src-resolve.4.2', E.ConstraintCode, 'xs:myT without an import: ' + E.Message);
        CheckEqualsStr(ExpandFileName(C), E.SchemaFile, 'xs:myT without an import: file');
      end;
    end;
    { with the import in c as well, it loads }
    WriteTestFile(C, '<xs:schema xmlns:xs="' + XsNs + '"><xs:import namespace="' + XsNs +
      '"/><xs:element name="c" type="xs:myT"/></xs:schema>');
    S := LandrixXmlXsdLoadSchema(A);
    Check(S.FindElement('', 'c') <> nil, 'xs:myT with an import');
  finally
    S.Free;
    DeleteFile(A);
    DeleteFile(B);
    DeleteFile(C);
  end;
end;

{ the name map after removals (a redefinition takes a type out of the
  map of its kind): every other key is still found, through collisions
  and after growing }
procedure TestNameMapRemove;
var
  Map: TLandrixXmlXsdNameMap;
  Values: TObjectList;
  I, Round: Integer;
  Gone: Boolean;

  function Key(I: Integer): TLandrixXmlUtf8;
  begin
    Result := LandrixXmlStringToUtf8('n' + IntToStr(I));
  end;

begin
  Values := TObjectList.Create(True);
  Map := TLandrixXmlXsdNameMap.Create;
  try
    Map.Remove('', 'missing');
    for I := 0 to 299 do
    begin
      Values.Add(TObject.Create);
      Map.Put('urn:x', Key(I), Values[I]);
    end;
    for Round := 2 to 3 do
    begin
      for I := 299 downto 0 do
        if I mod Round = 0 then
          Map.Remove('urn:x', Key(I));
      Map.Remove('urn:x', 'missing');
      for I := 0 to 299 do
      begin
        Gone := (I mod 2 = 0) or ((Round = 3) and (I mod 3 = 0));
        if Gone then
          Check(Map.Find('urn:x', Key(I)) = nil, 'removed ' + IntToStr(I))
        else
          Check(Map.Find('urn:x', Key(I)) = Values[I], 'kept ' + IntToStr(I));
      end;
    end;
    CheckEquals(100, Map.Count, 'count after removal');
    for I := 0 to 299 do
      Map.Put('urn:x', Key(I), Values[I]);
    CheckEquals(300, Map.Count, 'count after adding again');
    for I := 0 to 299 do
      Check(Map.Find('urn:x', Key(I)) = Values[I], 'again ' + IntToStr(I));
  finally
    Map.Free;
    Values.Free;
  end;
end;

{ tests/data/xsdschema/rules.txt: schemas with the constraint code Xerces
  reports (a sixth field holds Xerces' code where it is known to differ),
  and valid forms that must load (tools/check-xsdrules.py checks the codes
  against the JDK). A form feed in the body starts a second document,
  written next to the first, whose name replaces %B% in the first. }
procedure TestSchemaRules;
var
  L, Fields: TStringList;
  K, Count, P: Integer;
  FileName, Body, Root, Second, SecondFile: string;
  S: TLandrixXmlXsdSchemaSet;
begin
  Count := 0;
  L := TStringList.Create;
  try
    L.LoadFromFile(IncludeTrailingPathDelimiter(RepositoryRoot) + 'tests' + PathDelim + 'data' + PathDelim +
      'xsdschema' + PathDelim + 'rules.txt');
    for K := 0 to Integer(L.Count) - 1 do
    begin
      if (L[K] = '') or (L[K][1] = '#') then
        Continue;
      Fields := SplitTabs(L[K]);
      try
        Check((Integer(Fields.Count) = 5) or (Integer(Fields.Count) = 6), 'rules.txt line ' + IntToStr(K + 1));
        if (Integer(Fields.Count) <> 5) and (Integer(Fields.Count) <> 6) then
          Continue;
        Inc(Count);
        Body := LandrixXmlUtf8ToString(Unescaped(Fields[4]));
        Root := LandrixXmlUtf8ToString(Unescaped(Fields[3]));
        SecondFile := '';
        P := Pos(#12, Body);
        if P > 0 then
        begin
          Second := Copy(Body, P + 1, MaxInt);
          Body := Copy(Body, 1, P - 1);
          SecondFile := ExtractFilePath(ParamStr(0)) + 'xsdrule-' + IntToStr(K) + '-b.xsd';
          if Copy(Second, 1, 10) = '<xs:schema' then
            WriteTestFile(SecondFile, Second)
          else
            WriteTestFile(SecondFile, '<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"' + Root + '>' +
              Second + '</xs:schema>');
          Body := StringReplace(Body, '%B%', ExtractFileName(SecondFile), [rfReplaceAll]);
        end;
        try
          if Fields[0] <> 'valid' then
            CheckSchemaRule(Body, Fields[0], StrToInt(Fields[1]), Fields[2], Root)
          else
          begin
            FileName := TempSchema(Body, Root);
            S := nil;
            try
              S := LandrixXmlXsdLoadSchema(FileName);
              Check(S.FindElement('', 'r') <> nil, Fields[2] + ' load');
            finally
              S.Free;
              DeleteFile(FileName);
            end;
          end;
        finally
          if SecondFile <> '' then
            DeleteFile(SecondFile);
        end;
      finally
        Fields.Free;
      end;
    end;
  finally
    L.Free;
  end;
  Check(Count >= 60, 'rules.txt read');
end;

{ A white space reference in element-only content, a syntax error after
  MaxErrors, a document without a root element. }
procedure TestReaderEdges;
var
  FileName: string;
  S: TLandrixXmlXsdSchemaSet;
  V: TLandrixXmlXsdValidator;
  Reader: TLandrixXmlReader;
  Doc: TLandrixXmlDocument;
  Raised: Boolean;
begin
  FileName := TempSchema('<xs:element name="e"><xs:complexType><xs:sequence>' +
    '<xs:element name="c" maxOccurs="2"/></xs:sequence></xs:complexType></xs:element>' +
    '<xs:element name="i" type="xs:int"/>');
  S := LandrixXmlXsdLoadSchema(FileName);
  V := TLandrixXmlXsdValidator.Create(S);
  Reader := TLandrixXmlReader.Create;
  Doc := TLandrixXmlDocument.Create;
  try
    Reader.LoadFromUtf8(U('<e>&#32;<c/>&#x9;&#10;<c/></e>'));
    Check(V.ValidateReader(Reader), 'character references to white space in element-only content');
    Reader.LoadFromUtf8(U('<e>&#65;<c/></e>'));
    Check(not V.ValidateReader(Reader), 'a reference to a letter is character content');
    { the limit stops collecting errors, not reading }
    V.MaxErrors := 1;
    Reader.LoadFromUtf8(U('<i>x</i><'));
    Raised := False;
    try
      V.ValidateReader(Reader);
    except
      on E: ELandrixXmlError do
        Raised := E.Code = xecSyntax;
    end;
    Check(Raised, 'a syntax error after the last collected error');
    V.MaxErrors := 1000;
    Raised := False;
    try
      V.ValidateDocument(Doc);
    except
      on E: ELandrixXmlError do
        Raised := E.Code = xecInvalidArgument;
    end;
    Check(Raised, 'a document without a root element');
  finally
    Doc.Free;
    Reader.Free;
    V.Free;
    S.Free;
    DeleteFile(FileName);
  end;
end;

procedure Register;
begin
  RegisterTest('XsdValidator.Basics', TestBasics);
  RegisterTest('XsdValidator.Derivation', TestDerivation);
  RegisterTest('XsdValidator.NameMapRemove', TestNameMapRemove);
  RegisterTest('XsdValidator.Wildcards', TestWildcards);
  RegisterTest('XsdValidator.Identity', TestIdentity);
  RegisterTest('XsdValidator.Occurrence', TestOccurrence);
  RegisterTest('XsdValidator.Values', TestValues);
  RegisterTest('XsdValidator.EdgeCases', TestEdgeCases);
  RegisterTest('XsdValidator.KeyRefOutOfScope', TestKeyRefOutOfScope);
  RegisterTest('XsdValidator.CompositeKeySeparator', TestCompositeKeySeparator);
  RegisterTest('XsdValidator.ManyChildNames', TestManyChildNames);
  RegisterTest('XsdValidator.TypeDerivation', TestTypeDerivation);
  RegisterTest('XsdValidator.LoadErrors', TestLoadErrors);
  RegisterTest('XsdValidator.LargeOccurs', TestLargeOccurs);
  RegisterTest('XsdValidator.ContentLimits', TestContentLimits);
  RegisterTest('XsdValidator.Unresolved', TestUnresolved);
  RegisterTest('XsdValidator.SchemaRules', TestSchemaRules);
  RegisterTest('XsdValidator.XsNamespaceImport', TestXsNamespaceImport);
  {$IFDEF MSWINDOWS}
  RegisterTest('XsdValidator.FileCase', TestFileCase);
  {$ENDIF}
  {$IFDEF LINUX}
  RegisterTest('XsdValidator.FileCaseLinux', TestFileCaseLinux);
  {$ENDIF}
  RegisterTest('XsdValidator.Api', TestApi);
  RegisterTest('XsdValidator.ReaderEdges', TestReaderEdges);
end;

end.
