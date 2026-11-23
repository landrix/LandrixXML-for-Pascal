{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Tests for the XSLT processor: the cases in tests/data/xslt (expected
  output or error code from Saxon HE, tools/gen-xslt-testdata.py), byte by
  byte, plus the API. }

unit LandrixXmlTestXslt;

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
  LandrixXmlXslt,
  LandrixXmlXsltOutput,
  LandrixXmlTestFramework;

function U(const S: string): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(S);
end;

function DataFolder: string;
begin
  Result := IncludeTrailingPathDelimiter(RepositoryRoot) + 'tests' + PathDelim + 'data' + PathDelim + 'xslt' +
    PathDelim;
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

{ the output of a case, or "error CODE" }
function RunCase(const Name: string): TLandrixXmlUtf8;
var
  Sheet: TLandrixXmlXsltStylesheet;
  T: TLandrixXmlXsltTransformer;
  Source: TLandrixXmlXPathTree;
  Output: TMemoryStream;
begin
  Result := '';
  Sheet := TLandrixXmlXsltStylesheet.Create;
  T := nil;
  Source := TLandrixXmlXPathTree.Create;
  Output := TMemoryStream.Create;
  try
    try
      Sheet.LoadFromFile(DataFolder + Name + '.xsl');
      if FileExists(DataFolder + Name + '.xml') then
        Source.LoadFromFile(DataFolder + Name + '.xml')
      else
        Source.LoadFromUtf8(U('<doc/>'));
      T := TLandrixXmlXsltTransformer.Create(Sheet);
      T.Transform(Source, Output);
      SetLength(Result, Output.Size);
      if Output.Size > 0 then
        Move(Output.Memory^, Result[1], Integer(Output.Size));
    except
      on E: ELandrixXmlXPathError do
        Result := U('error ' + E.XPathCode);
    end;
  finally
    Output.Free;
    Source.Free;
    T.Free;
    Sheet.Free;
  end;
end;

procedure TestCases;
var
  SR: TSearchRec;
  Name: string;
  Expected: TLandrixXmlUtf8;
  Count: Integer;
begin
  Count := 0;
  if FindFirst(DataFolder + '*.xsl', faAnyFile, SR) = 0 then
    try
      repeat
        if Copy(SR.Name, 1, 1) = '_' then
          Continue;
        Name := ChangeFileExt(SR.Name, '');
        { the expected output as bytes (a string would lose what the
          platform's code page has not) }
        if FileExists(DataFolder + Name + '.err') then
          Expected := U('error ' + Trim(LandrixXmlUtf8ToString(FileBytes(DataFolder + Name + '.err'))))
        else
          Expected := FileBytes(DataFolder + Name + '.out');
        CheckEqualsUtf8(Expected, RunCase(Name), 'case ' + Name);
        Inc(Count);
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  Check(Count > 0, 'cases found');
end;

{ Parameters of the three kinds, the initial template, TransformToTree,
  messages, errors with their position. }
procedure TestApi;
var
  Sheet: TLandrixXmlXsltStylesheet;
  T: TLandrixXmlXsltTransformer;
  Source, Param, Target: TLandrixXmlXPathTree;
  Raised: string;
begin
  Sheet := TLandrixXmlXsltStylesheet.Create;
  T := nil;
  Source := TLandrixXmlXPathTree.Create;
  Param := TLandrixXmlXPathTree.Create;
  Target := TLandrixXmlXPathTree.Create;
  try
    Sheet.LoadFromUtf8(U(
      '<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"' +
      ' xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:n="urn:n" exclude-result-prefixes="xs n">' +
      '<xsl:param name="s"/><xsl:param name="i" as="xs:integer" select="0"/>' +
      '<xsl:param name="n:doc" required="yes"/><xsl:param name="x" select="()"/>' +
      '<xsl:output omit-xml-declaration="yes"/>' +
      '<xsl:template match="/"><r s="{$s}" i="{$i + 1}" d="{$n:doc/*/@v}" x="{$x}"/>' +
      '<xsl:message>m1</xsl:message></xsl:template>' +
      '<xsl:template name="start"><start/></xsl:template>' +
      '</xsl:stylesheet>'), U('urn:test'));
    CheckEquals(4, Sheet.ParameterCount, 'parameter count');
    CheckEqualsUtf8(U('{urn:n}doc'), Sheet.ParameterNames[2], 'a parameter name in Clark notation');
    Check(Sheet.ParameterRequired[2] and not Sheet.ParameterRequired[0], 'required');
    Raised := '';
    try
      Sheet.LoadFromUtf8(U('<x/>'), U(''));
    except
      on E: ELandrixXmlError do
        Raised := IntToStr(Ord(E.Code));
    end;
    CheckEqualsStr(IntToStr(Ord(xecInvalidOperation)), Raised, 'a second load');
    Source.LoadFromUtf8(U('<doc/>'));
    Param.LoadFromUtf8(U('<p v="tree"/>'));
    T := TLandrixXmlXsltTransformer.Create(Sheet);
    Raised := '';
    try
      T.TransformToUtf8(Source);
    except
      on E: ELandrixXmlXsltError do
        Raised := E.XPathCode;
    end;
    CheckEqualsStr('XTDE0050', Raised, 'a required parameter missing');
    T.SetParameter(U('s'), U('str'));
    T.SetParameter(U('i'), U('41'));
    T.SetParameterTree(U('{urn:n}doc'), Param);
    T.SetParameterXPath(U('x'), U('(1, 2) +'));
    Raised := '';
    try
      T.TransformToUtf8(Source);
    except
      on E: ELandrixXmlXPathError do
        Raised := E.XPathCode;
    end;
    CheckEqualsStr('XPST0003', Raised, 'a syntax error in an XPath parameter');
    T.SetParameterXPath(U('x'), U('(1, 2)'));
    CheckEqualsUtf8(U('<r s="str" i="42" d="tree" x="1 2"/>'), T.TransformToUtf8(Source), 'the parameters');
    CheckEquals(1, T.MessageCount, 'a message');
    CheckEqualsUtf8(U('m1'), T.Messages[0].TextUtf8, 'its text');
    T.TransformToTree(Source, Target);
    CheckEqualsUtf8(U('r'), Target.LocalNameUtf8(Target.DocumentElement), 'TransformToTree');
    T.InitialTemplate := U('start');
    CheckEqualsUtf8(U('<start/>'), T.TransformToUtf8(nil), 'an initial template without source');
    T.InitialTemplate := U('none');
    Raised := '';
    try
      T.TransformToUtf8(Source);
    except
      on E: ELandrixXmlXPathError do
        Raised := E.XPathCode;
    end;
    CheckEqualsStr('XTDE0040', Raised, 'an unknown initial template');
    T.InitialTemplate := '';
    T.SetOutputProperty(U('omit-xml-declaration'), U('no'));
    CheckEqualsUtf8(U('<?xml version="1.0" encoding="UTF-8"?><r s="str" i="42" d="tree" x="1 2"/>'),
      T.TransformToUtf8(Source), 'an output property set by the caller');
    Raised := '';
    try
      T.SetOutputProperty(U('html-version'), U('5'));
    except
      on E: ELandrixXmlError do
        Raised := IntToStr(Ord(E.Code));
    end;
    CheckEqualsStr(IntToStr(Ord(xecUnsupported)), Raised, 'an output property the serializer does not do');
    Raised := '';
    try
      T.SetOutputProperty(U('colour'), U('red'));
    except
      on E: ELandrixXmlError do
        Raised := IntToStr(Ord(E.Code));
    end;
    CheckEqualsStr(IntToStr(Ord(xecInvalidArgument)), Raised, 'an output property XSLT does not define');
  finally
    T.Free;
    Target.Free;
    Param.Free;
    Source.Free;
    Sheet.Free;
  end;
end;

{ Without a source the globals have no context item; the text of a
  message is that of the document its content builds. }
procedure TestNoSource;
var
  Sheet: TLandrixXmlXsltStylesheet;
  T: TLandrixXmlXsltTransformer;
  Raised: string;
begin
  Sheet := TLandrixXmlXsltStylesheet.Create;
  T := nil;
  try
    Sheet.LoadFromUtf8(U(
      '<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">' +
      '<xsl:output omit-xml-declaration="yes"/>' +
      '<xsl:variable name="g" select="name(/*)"/>' +
      '<xsl:template name="start"><xsl:message><xsl:sequence select="(1, 2)"/></xsl:message>' +
      '<r><xsl:value-of select="$g"/></r></xsl:template>' +
      '<xsl:template name="quiet"><r/></xsl:template>' +
      '<xsl:variable name="c" select="current()"/>' +
      '<xsl:template name="cur"><xsl:for-each select="1"><xsl:value-of select="$c"/></xsl:for-each></xsl:template>' +
      '</xsl:stylesheet>'), U('urn:test'));
    T := TLandrixXmlXsltTransformer.Create(Sheet);
    T.InitialTemplate := U('quiet');
    CheckEqualsUtf8(U('<r/>'), T.TransformToUtf8(nil), 'a global that is not used');
    T.InitialTemplate := U('start');
    Raised := '';
    try
      T.TransformToUtf8(nil);
    except
      on E: ELandrixXmlXPathError do
        Raised := E.XPathCode;
    end;
    CheckEqualsStr('XPDY0002', Raised, 'a global that uses the context without a source');
    CheckEquals(1, T.MessageCount, 'the message before');
    CheckEqualsUtf8(U('1 2'), T.Messages[0].TextUtf8, 'atomic values in a message');
    T.InitialTemplate := U('cur');
    Raised := '';
    try
      T.TransformToUtf8(nil);
    except
      on E: ELandrixXmlXPathError do
        Raised := E.XPathCode;
    end;
    CheckEqualsStr('XPDY0002', Raised, 'current() in a global without a source');
  finally
    T.Free;
    Sheet.Free;
  end;
end;

{ system-property(): the values that are this processor's, not Saxon's }
procedure TestSystemProperty;
var
  Sheet: TLandrixXmlXsltStylesheet;
  T: TLandrixXmlXsltTransformer;
begin
  Sheet := TLandrixXmlXsltStylesheet.Create;
  T := nil;
  try
    Sheet.LoadFromUtf8(U(
      '<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"' +
      ' xmlns:x="http://www.w3.org/1999/XSL/Transform">' +
      '<xsl:output method="text"/>' +
      '<xsl:template name="main"><xsl:value-of separator="|" select="system-property(''xsl:version''),' +
      ' system-property(''x:vendor''), system-property(''xsl:vendor-url''),' +
      ' system-property(''xsl:product-name''), system-property(''xsl:product-version''),' +
      ' system-property(''xsl:supports-backwards-compatibility'')"/></xsl:template>' +
      '</xsl:stylesheet>'), U('urn:test'));
    T := TLandrixXmlXsltTransformer.Create(Sheet);
    T.InitialTemplate := U('main');
    CheckEqualsUtf8(U('2.0|Landrix Software|https://github.com/landrix/LandrixXML-for-Pascal|LandrixXML|' +
      LandrixXmlVersion + '|yes'), T.TransformToUtf8(nil), 'system-property()');
  finally
    T.Free;
    Sheet.Free;
  end;
end;

{ An attribute in a message is its value (as Saxon prints it). }
procedure TestMessages;
var
  Sheet: TLandrixXmlXsltStylesheet;
  T: TLandrixXmlXsltTransformer;
  Source: TLandrixXmlXPathTree;
begin
  Sheet := TLandrixXmlXsltStylesheet.Create;
  Source := TLandrixXmlXPathTree.Create;
  T := nil;
  try
    Sheet.LoadFromUtf8(U(
      '<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">' +
      '<xsl:output omit-xml-declaration="yes"/>' +
      '<xsl:template match="/"><xsl:message select="/r/@id"/><xsl:message select="/r/@id, ''x''"/>' +
      '<xsl:message><xsl:attribute name="q">v</xsl:attribute></xsl:message><ok/></xsl:template>' +
      '</xsl:stylesheet>'), U('urn:test'));
    Source.LoadFromUtf8(U('<r id="7"/>'));
    T := TLandrixXmlXsltTransformer.Create(Sheet);
    CheckEqualsUtf8(U('<ok/>'), T.TransformToUtf8(Source), 'the result');
    CheckEquals(3, T.MessageCount, 'the messages');
    CheckEqualsUtf8(U('7'), T.Messages[0].TextUtf8, 'an attribute');
    CheckEqualsUtf8(U('7x'), T.Messages[1].TextUtf8, 'an attribute and a string');
    CheckEqualsUtf8(U('v'), T.Messages[2].TextUtf8, 'an attribute made in the message');
  finally
    T.Free;
    Source.Free;
    Sheet.Free;
  end;
end;

{ xsl:result-document: secondary results collected by the transformer
  (URIs resolved against BaseOutputUri), empty after an error; a relative
  href needs a base output URI. }
procedure TestResultDocuments;
const
  Sheet1 = '<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">' +
    '<xsl:output omit-xml-declaration="yes"/><xsl:output name="t" method="text"/>' +
    '<xsl:param name="twice" select="false()"/>' +
    '<xsl:template match="/"><main/>' +
    '<xsl:result-document href="a.txt" format="t"><a>text</a></xsl:result-document>' +
    '<xsl:result-document href="sub/../b.xml" omit-xml-declaration="{''yes''}"><b/></xsl:result-document>' +
    '<xsl:if test="$twice"><xsl:result-document href="b.xml"><c/></xsl:result-document></xsl:if>' +
    '</xsl:template></xsl:stylesheet>';
var
  Sheet: TLandrixXmlXsltStylesheet;
  T: TLandrixXmlXsltTransformer;
  Source: TLandrixXmlXPathTree;
  Doc: TLandrixXmlXsltResultDocument;
  Code: string;
begin
  Sheet := TLandrixXmlXsltStylesheet.Create;
  Source := TLandrixXmlXPathTree.Create;
  T := nil;
  try
    Sheet.LoadFromUtf8(U(Sheet1), U('urn:test'));
    Source.LoadFromUtf8(U('<doc/>'));
    T := TLandrixXmlXsltTransformer.Create(Sheet);
    { no base output URI: a relative href is an error }
    Code := 'none';
    try
      T.TransformToUtf8(Source);
    except
      on E: ELandrixXmlXsltError do
        Code := E.XPathCode;
    end;
    CheckEqualsStr('FOER0000', Code, 'a relative href without a base output URI');
    CheckEquals(0, T.ResultDocumentCount, 'no results after an error');
    Code := 'none';
    try
      T.BaseOutputUri := U('out/main.xml');
    except
      on E: ELandrixXmlError do
        Code := IntToStr(Ord(E.Code));
    end;
    CheckEqualsStr(IntToStr(Ord(xecInvalidArgument)), Code, 'a relative base output URI');
    Code := 'none';
    try
      T.BaseOutputUri := U('C:\out\main.xml');
    except
      on E: ELandrixXmlError do
        Code := IntToStr(Ord(E.Code));
    end;
    CheckEqualsStr(IntToStr(Ord(xecInvalidArgument)), Code, 'a file name as the base output URI');
    T.BaseOutputUri := U('file:///out/main.xml');
    CheckEqualsUtf8(U('<main/>'), T.TransformToUtf8(Source), 'the principal result');
    CheckEquals(2, T.ResultDocumentCount, 'two result documents');
    CheckEqualsUtf8(U('file:///out/a.txt'), T.ResultDocuments[0].Uri, 'the first URI');
    CheckEqualsUtf8(U('text'), T.ResultDocuments[0].SerializeToUtf8, 'the named format');
    CheckEqualsUtf8(U('text'), T.ResultDocuments[0].OutputProperty(U('method')), 'its method');
    Doc := T.FindResultDocument(U('file:///out/b.xml'));
    Check(Doc <> nil, 'found by its URI');
    if Doc <> nil then
    begin
      CheckEqualsUtf8(U('<b/>'), Doc.SerializeToUtf8, 'a computed attribute');
      CheckEqualsUtf8(U('file:///out/b.xml'), Doc.Tree.BaseUri, 'the base URI of the tree');
    end;
    Check(T.FindResultDocument(U('file:///out/c.xml')) = nil, 'no such result');
    { two results with the same URI }
    T.SetParameterXPath(U('twice'), U('true()'));
    Code := 'none';
    try
      T.TransformToUtf8(Source);
    except
      on E: ELandrixXmlXsltError do
        Code := E.XPathCode;
    end;
    CheckEqualsStr('XTDE1490', Code, 'the same URI twice');
    CheckEquals(0, T.ResultDocumentCount, 'none kept after the error');
  finally
    T.Free;
    Source.Free;
    Sheet.Free;
  end;
end;

{ xsl:analyze-string clears the current template rule (XSLT 2.0, 5.4.4;
  Saxon keeps it and applies the built-in rule to the string). }
procedure TestNextMatchInAnalyzeString;
var
  Sheet: TLandrixXmlXsltStylesheet;
  T: TLandrixXmlXsltTransformer;
  Source: TLandrixXmlXPathTree;
  Code: string;
begin
  Sheet := TLandrixXmlXsltStylesheet.Create;
  Source := TLandrixXmlXPathTree.Create;
  T := nil;
  try
    Sheet.LoadFromUtf8(U(
      '<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">' +
      '<xsl:template match="/"><xsl:analyze-string select="''q''" regex="q">' +
      '<xsl:matching-substring><xsl:next-match/></xsl:matching-substring></xsl:analyze-string></xsl:template>' +
      '</xsl:stylesheet>'), U('urn:test'));
    Source.LoadFromUtf8(U('<r/>'));
    T := TLandrixXmlXsltTransformer.Create(Sheet);
    Code := 'none';
    try
      T.TransformToUtf8(Source);
    except
      on E: ELandrixXmlXsltError do
        Code := E.XPathCode;
    end;
    CheckEqualsStr('XTDE0560', Code, 'xsl:next-match in xsl:analyze-string');
  finally
    T.Free;
    Source.Free;
    Sheet.Free;
  end;
end;

{ A stylesheet without a base URI reads documents the resolver has under
  a relative or a single-letter scheme name, with document#1 (the empty
  base is left to the resolver) and doc(). }
procedure TestDocumentWithoutBase;
var
  Sheet: TLandrixXmlXsltStylesheet;
  T: TLandrixXmlXsltTransformer;
  Source: TLandrixXmlXPathTree;
  Resolver: TLandrixXmlXsltResolver;
begin
  Sheet := TLandrixXmlXsltStylesheet.Create;
  Source := TLandrixXmlXPathTree.Create;
  Resolver := TLandrixXmlXsltResolver.Create;
  T := nil;
  try
    Sheet.LoadFromUtf8(U(
      '<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">' +
      '<xsl:output omit-xml-declaration="yes"/>' +
      '<xsl:template match="/"><r><xsl:value-of select="document(''codes.xml'')/c, document(''x:d'')/d, ' +
      'doc(''codes.xml'')/c"/></r></xsl:template>' +
      '</xsl:stylesheet>'), U(''));
    Resolver.AddUtf8(U('codes.xml'), U('<c>1</c>'));
    Resolver.AddUtf8(U('x:d'), U('<d>2</d>'));
    Source.LoadFromUtf8(U('<s/>'));
    T := TLandrixXmlXsltTransformer.Create(Sheet);
    T.Resolver := Resolver;
    CheckEqualsUtf8(U('<r>1 2 1</r>'), T.TransformToUtf8(Source), 'resolver documents without a base URI');
  finally
    T.Free;
    Resolver.Free;
    Source.Free;
    Sheet.Free;
  end;
end;

function Utf8Bytes(const Codes: array of Byte): TLandrixXmlUtf8;
var
  I: Integer;
begin
  Result := '';
  SetLength(Result, Length(Codes));
  for I := 0 to Integer(High(Codes)) do
    Result[I + 1] := AnsiChar(Codes[I]);
end;

{ xsl:key and for-each-group keep keys apart that the system code page
  cannot represent (Delphi 6-2007 and FPC on Windows converted them to
  '?' before): Cyrillic ab and vg. }
procedure TestKeysOutsideCodePage;
var
  Sheet: TLandrixXmlXsltStylesheet;
  T: TLandrixXmlXsltTransformer;
  Source: TLandrixXmlXPathTree;
begin
  Sheet := TLandrixXmlXsltStylesheet.Create;
  Source := TLandrixXmlXPathTree.Create;
  T := nil;
  try
    Sheet.LoadFromUtf8(U(
      '<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">' +
      '<xsl:output omit-xml-declaration="yes"/><xsl:key name="k" match="i" use="@k"/>' +
      '<xsl:template match="/"><r><xsl:value-of select="key(''k'', string(r/i[1]/@k))"/>' +
      '<xsl:for-each-group select="r/i" group-by="@k"><g><xsl:value-of select="current-group()"/></g>' +
      '</xsl:for-each-group></r></xsl:template></xsl:stylesheet>'), U(''));
    Source.LoadFromUtf8(U('<r><i k="') + Utf8Bytes([$D0, $B0, $D0, $B1]) + U('">A</i><i k="') +
      Utf8Bytes([$D0, $B2, $D0, $B3]) + U('">B</i></r>'));
    T := TLandrixXmlXsltTransformer.Create(Sheet);
    CheckEqualsUtf8(U('<r>A<g>A</g><g>B</g></r>'), T.TransformToUtf8(Source), 'two keys, two groups');
  finally
    T.Free;
    Source.Free;
    Sheet.Free;
  end;
end;

{ names of templates, modes, global variables and decimal formats that the system code
  page cannot represent stay apart (Delphi 6-2007 made both '?' and
  reported XTSE0630 for the variables): Cyrillic ab and vg }
procedure TestNamesOutsideCodePage;
var
  Sheet: TLandrixXmlXsltStylesheet;
  T: TLandrixXmlXsltTransformer;
  Source: TLandrixXmlXPathTree;
  A, B: TLandrixXmlUtf8;
begin
  A := Utf8Bytes([$D0, $B0, $D0, $B1]);
  B := Utf8Bytes([$D0, $B2, $D0, $B3]);
  Sheet := TLandrixXmlXsltStylesheet.Create;
  Source := TLandrixXmlXPathTree.Create;
  T := nil;
  try
    Sheet.LoadFromUtf8(U('<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">' +
      '<xsl:output omit-xml-declaration="yes"/><xsl:variable name="v') + A + U('" select="1"/>' +
      '<xsl:variable name="v') + B + U('" select="2"/><xsl:decimal-format name="f') + A +
      U('" decimal-separator="," grouping-separator="."/><xsl:decimal-format name="f') + B +
      U('" decimal-separator=";" pattern-separator="|"/>' +
      '<xsl:template match="/"><r>' +
      '<xsl:call-template name="t') + A + U('"/><xsl:call-template name="t') + B + U('"/>' +
      '<xsl:value-of select="$v') + A + U(', $v') + B + U('"/>' +
      '<xsl:value-of select="format-number(1.5, ''0,0'', ''f') + A + U(''')"/>' +
      '<xsl:value-of select="format-number(1.5, ''0;0'', ''f') + B + U(''')"/>' +
      '<xsl:apply-templates select="." mode="m') + A + U('"/><xsl:apply-templates select="." mode="m') + B +
      U('"/></r></xsl:template><xsl:template name="t') + A + U('">a</xsl:template>' +
      '<xsl:template name="t') + B + U('">b</xsl:template><xsl:template match="/" mode="m') + A +
      U('">c</xsl:template><xsl:template match="/" mode="m') + B + U('">d</xsl:template>' +
      '</xsl:stylesheet>'), U(''));
    Source.LoadFromUtf8(U('<doc/>'));
    T := TLandrixXmlXsltTransformer.Create(Sheet);
    CheckEqualsUtf8(U('<r>ab1 21,51;5cd</r>'), T.TransformToUtf8(Source), 'two names each');
  finally
    T.Free;
    Source.Free;
    Sheet.Free;
  end;
end;

function CompileCode(const Main, Imp: string): string; forward;

{ the code of compiling S, 'ok' if it compiles }
function CompileUtf8(const S: TLandrixXmlUtf8): string;
var
  Sheet: TLandrixXmlXsltStylesheet;
begin
  Sheet := TLandrixXmlXsltStylesheet.Create;
  try
    Result := 'ok';
    try
      Sheet.LoadFromUtf8(S, U(''));
    except
      on E: ELandrixXmlXPathError do
        Result := E.XPathCode;
    end;
  finally
    Sheet.Free;
  end;
end;

{ a name with a character that is no name character (NBSP) is a static
  error, as with Saxon (non-ASCII letters stay allowed) }
procedure TestNonNameCharacter;
var
  Sheet: TLandrixXmlXsltStylesheet;
  Code: string;
begin
  CheckEqualsStr('XTSE0020', CompileUtf8(U('<xsl:stylesheet version="2.0" ' +
    'xmlns:xsl="http://www.w3.org/1999/XSL/Transform"><xsl:decimal-format name="a') + Utf8Bytes([$C2, $A0]) +
    U('b"/></xsl:stylesheet>')), 'NBSP in a decimal format name');
  Sheet := TLandrixXmlXsltStylesheet.Create;
  try
    Code := 'ok';
    try
      Sheet.LoadFromUtf8(U('<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">' +
        '<xsl:template name="a') + Utf8Bytes([$C2, $A0]) + U('b"/></xsl:stylesheet>'), U(''));
    except
      on E: ELandrixXmlXPathError do
        Code := E.XPathCode;
    end;
    CheckEqualsStr('XTSE0020', Code, 'NBSP in a template name');
    CheckEqualsStr('XTSE0020', CompileCode('<xsl:stylesheet version="2.0" ' +
      'xmlns:xsl="http://www.w3.org/1999/XSL/Transform"><xsl:template name="1p:t"/></xsl:stylesheet>', ''),
      'a malformed prefix before its lookup');
    CheckEqualsStr('XTSE0280', CompileCode('<xsl:stylesheet version="2.0" ' +
      'xmlns:xsl="http://www.w3.org/1999/XSL/Transform"><xsl:template name="p:t"/></xsl:stylesheet>', ''),
      'an undeclared prefix');
    CheckEqualsStr('ok', CompileCode('<xsl:stylesheet version="2.0" ' +
      'xmlns:xsl="http://www.w3.org/1999/XSL/Transform"><xsl:template match="/">' +
      '<xsl:apply-templates mode="#unnamed"/></xsl:template></xsl:stylesheet>', ''),
      'mode #unnamed in apply-templates');
  finally
    Sheet.Free;
  end;
end;

{ byte-order-mark: written for UTF-8 only, also by TransformToUtf8 (not
  when another encoding is asked for) }
procedure TestByteOrderMark;
const
  Sheet1 = '<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">' +
    '<xsl:output omit-xml-declaration="yes" byte-order-mark="yes" encoding="%s"/>' +
    '<xsl:template name="main"><a/></xsl:template></xsl:stylesheet>';
  Encodings: array[0..2] of string = ('UTF-8', 'utf8', 'ISO-8859-1');
var
  Sheet: TLandrixXmlXsltStylesheet;
  T: TLandrixXmlXsltTransformer;
  I: Integer;
  Bom, Expected: TLandrixXmlUtf8;
  Stream: TMemoryStream;
  Code: string;
begin
  Bom := '';
  SetLength(Bom, 3);
  Bom[1] := AnsiChar($EF);
  Bom[2] := AnsiChar($BB);
  Bom[3] := AnsiChar($BF);
  for I := 0 to High(Encodings) do
  begin
    Expected := U('<a/>');
    if I < 2 then
      Expected := Bom + Expected;
    Sheet := TLandrixXmlXsltStylesheet.Create;
    T := nil;
    try
      Sheet.LoadFromUtf8(U(StringReplace(Sheet1, '%s', Encodings[I], [])), U('urn:case'));
      T := TLandrixXmlXsltTransformer.Create(Sheet);
      T.InitialTemplate := U('main');
      CheckEqualsUtf8(Expected, T.TransformToUtf8(nil), 'byte-order-mark: ' + Encodings[I]);
    finally
      T.Free;
      Sheet.Free;
    end;
  end;
  { an unsupported setting is rejected before the byte order mark }
  Sheet := TLandrixXmlXsltStylesheet.Create;
  T := nil;
  Stream := TMemoryStream.Create;
  try
    Sheet.LoadFromUtf8(U('<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">' +
      '<xsl:output method="html" version="4.0" byte-order-mark="yes"/>' +
      '<xsl:template name="main"><html/></xsl:template></xsl:stylesheet>'), U('urn:case'));
    T := TLandrixXmlXsltTransformer.Create(Sheet);
    T.InitialTemplate := U('main');
    Code := 'none';
    try
      T.Transform(nil, Stream);
    except
      on E: ELandrixXmlError do
        Code := IntToStr(Ord(E.Code));
    end;
    CheckEqualsStr(IntToStr(Ord(xecUnsupported)), Code, 'byte-order-mark: html version 4.0');
    CheckEquals(0, Integer(Stream.Size), 'byte-order-mark: nothing written before the error');
  finally
    Stream.Free;
    T.Free;
    Sheet.Free;
  end;
end;

{ disable-output-escaping where Saxon keeps it but this processor cannot
  (raw text in a node built in a sequence, a raw text item put into a
  temporary tree, in xsl:document or xsl:copy of a document node):
  xecUnsupported at run time, with the line }
procedure TestRawUnsupported;
const
  Head = '<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:f="urn:f">' +
    '<xsl:function name="f:raw"><xsl:text disable-output-escaping="yes">&lt;c&gt;</xsl:text></xsl:function>' +
    '<xsl:function name="f:e" as="element()"><e><xsl:text disable-output-escaping="yes">&lt;e&gt;</xsl:text>' +
    '</e></xsl:function>'#10;
  Cases: array[0..3] of string = (
    '<xsl:template name="main"><out><xsl:sequence select="f:e()"/></out></xsl:template>',
    '<xsl:template name="main"><out><xsl:document><xsl:text disable-output-escaping="yes">&lt;d&gt;</xsl:text>' +
      '</xsl:document></out></xsl:template>',
    '<xsl:template name="main"><xsl:for-each select="$d"><xsl:copy><xsl:text disable-output-escaping="yes">' +
      '&lt;d&gt;</xsl:text></xsl:copy></xsl:for-each></xsl:template>' +
      '<xsl:variable name="d"><r/></xsl:variable>',
    '<xsl:template name="main"><xsl:variable name="w"><xsl:sequence select="f:raw()"/></xsl:variable>' +
      '<out><xsl:sequence select="$w"/></out></xsl:template>');
var
  Sheet: TLandrixXmlXsltStylesheet;
  T: TLandrixXmlXsltTransformer;
  I: Integer;
  Code: string;
begin
  for I := 0 to High(Cases) do
  begin
    Sheet := TLandrixXmlXsltStylesheet.Create;
    T := nil;
    try
      Sheet.LoadFromUtf8(U(Head + Cases[I] + '</xsl:stylesheet>'), U('urn:case'));
      T := TLandrixXmlXsltTransformer.Create(Sheet);
      T.InitialTemplate := U('main');
      Code := 'none';
      try
        T.TransformToUtf8(nil);
      except
        on E: ELandrixXmlXsltError do
        begin
          Code := IntToStr(Ord(E.Code)) + ' ' + E.XPathCode;
          Check(E.Line > 0, 'the line: ' + Cases[I]);
        end;
      end;
      CheckEqualsStr(IntToStr(Ord(xecUnsupported)) + ' FOER0000', Code, 'unsupported: ' + Cases[I]);
    finally
      T.Free;
      Sheet.Free;
    end;
  end;
end;

{ Number formats Saxon writes in a way this library does not follow:
  xecUnsupported when they run }
procedure TestNumberFormatUnsupported;
const
  Head = '<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" ' +
    'xmlns:xs="http://www.w3.org/2001/XMLSchema"><xsl:template name="main"><out>';
  Cases: array[0..4] of string = (
    '<xsl:value-of select="format-date(xs:date(''2013-09-23''), ''[Da,3]'')"/>',
    '<xsl:value-of select="format-date(xs:date(''2013-09-23''), ''[Da,3]'') = ''w'' and true()"/>',
    '<xsl:value-of select="format-date(xs:date(''2013-09-23''), ''[Dw,15]'')"/>',
    '<xsl:value-of select="format-date(xs:date(''2013-09-23''), ''[DWc]'')"/>',
    '<xsl:number value="3" format="wW"/>');
var
  Sheet: TLandrixXmlXsltStylesheet;
  T: TLandrixXmlXsltTransformer;
  I: Integer;
  Code: string;
begin
  for I := 0 to High(Cases) do
  begin
    Sheet := TLandrixXmlXsltStylesheet.Create;
    T := nil;
    try
      Sheet.LoadFromUtf8(U(Head + Cases[I] + '</out></xsl:template></xsl:stylesheet>'), U('urn:case'));
      T := TLandrixXmlXsltTransformer.Create(Sheet);
      T.InitialTemplate := U('main');
      Code := 'none';
      try
        T.TransformToUtf8(nil);
      except
        on E: ELandrixXmlError do
          Code := IntToStr(Ord(E.Code));
      end;
      CheckEqualsStr(IntToStr(Ord(xecUnsupported)), Code, 'unsupported: ' + Cases[I]);
    finally
      T.Free;
      Sheet.Free;
    end;
  end;
end;

{ What the subset does not support is rejected when the stylesheet is
  loaded (xecUnsupported); errors name module and line. }
procedure TestRejected;
const
  Head = '<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">';
  Cases: array[0..10] of string = (
    '<xsl:accumulator name="a" initial-value="0"/><xsl:template match="/"/>',
    '<xsl:output html-version="5"/><xsl:template match="/"/>',
    '<xsl:output encoding="UTF-16"/><xsl:template match="/"/>',
    '<xsl:template match="/"><xsl:for-each select="1"><xsl:sort lang="de"/></xsl:for-each></xsl:template>',
    '<xsl:key name="k" match="a" use="." collation="http://www.w3.org/2013/collation/UCA"/><xsl:template match="/"/>',
    '<xsl:template match="/"><xsl:try/></xsl:template>',
    '<xsl:import-schema namespace="urn:x"/><xsl:template match="/"/>',
    '<xsl:template match="/"><xsl:result-document validation="strict"/></xsl:template>',
    '<xsl:template match="/"><xsl:for-each select="1"><!--c--><xsl:sort lang="de"/></xsl:for-each></xsl:template>',
    '<xsl:output suppress-indentation="a"/><xsl:template match="/"/>',
    '<xsl:template match="/"><r xsl:type="x"/></xsl:template>');
var
  Sheet: TLandrixXmlXsltStylesheet;
  I: Integer;
  Code: string;
begin
  for I := 0 to High(Cases) do
  begin
    Sheet := TLandrixXmlXsltStylesheet.Create;
    try
      Code := 'none';
      try
        Sheet.LoadFromUtf8(U(Head + Cases[I] + '</xsl:stylesheet>'), U('urn:case'));
      except
        on E: ELandrixXmlError do
          Code := IntToStr(Ord(E.Code));
      end;
      CheckEqualsStr(IntToStr(Ord(xecUnsupported)), Code, 'rejected: ' + Cases[I]);
    finally
      Sheet.Free;
    end;
  end;
  { the position of an error }
  Sheet := TLandrixXmlXsltStylesheet.Create;
  try
    Code := '';
    try
      Sheet.LoadFromUtf8(U(Head + #10 + '<xsl:template match="/">' + #10 + '  <xsl:value-of select="1 +"/>' + #10 +
        '</xsl:template></xsl:stylesheet>'), U('urn:module'));
    except
      on E: ELandrixXmlXsltError do
      begin
        Code := E.XPathCode;
        CheckEquals(3, E.Line, 'the line of the instruction');
        CheckEqualsUtf8(U('urn:module'), E.ModuleUri, 'the module');
        CheckEquals(Ord(xecXPath), Ord(E.Code), 'an XPath expression that does not compile');
      end;
    end;
    CheckEqualsStr('XPST0003', Code, 'a syntax error');
  finally
    Sheet.Free;
  end;
end;

{ a tree built through the API has no depth limit: stripping and copying
  it (MaxStackBytes, or 10000 levels without a budget) and serializing a
  result (the default stack budget) raise FOER0000 (xecLimit) instead of
  overflowing the stack }
procedure TestDeepApiTree;
const
  Strip = '<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">' +
    '<xsl:strip-space elements="*"/><xsl:template match="/"><r/></xsl:template></xsl:stylesheet>';
  CopyOf = '<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">' +
    '<xsl:template match="/"><xsl:copy-of select="."/></xsl:template></xsl:stylesheet>';
var
  Source: TLandrixXmlXPathTree;
  I: Integer;

  function Outcome(E: ELandrixXmlError): string;
  begin
    if (E.Code = xecLimit) and (E is ELandrixXmlXPathError) and
      (ELandrixXmlXPathError(E).XPathCode = 'FOER0000') then
      Result := 'limit'
    else
      Result := E.Message;
  end;

  { the run into a tree (no serializer) }
  function Run(const Text: string; Budget: Integer): string;
  var
    Sheet: TLandrixXmlXsltStylesheet;
    T: TLandrixXmlXsltTransformer;
    Target: TLandrixXmlXPathTree;
  begin
    Sheet := TLandrixXmlXsltStylesheet.Create;
    T := nil;
    Target := TLandrixXmlXPathTree.Create;
    try
      Sheet.LoadFromUtf8(U(Text), U('urn:test'));
      T := TLandrixXmlXsltTransformer.Create(Sheet);
      T.MaxStackBytes := Budget;
      try
        T.TransformToTree(Source, Target);
        Result := 'ok';
      except
        on E: ELandrixXmlError do
          Result := Outcome(E);
      end;
    finally
      Target.Free;
      T.Free;
      Sheet.Free;
    end;
  end;

  function Serialize(const Method: string): string;
  var
    Props: TXsltOutputProperties;
    M: TMemoryStream;
  begin
    Props := TXsltOutputProperties.Create;
    M := TMemoryStream.Create;
    try
      Props.SetValue('method', U(Method));
      { no indentation: its spaces grow with the square of the depth }
      Props.SetValue('indent', 'no');
      try
        XsltSerialize(Source, Props, M, False);
        Result := 'ok';
      except
        on E: ELandrixXmlError do
          Result := Outcome(E);
      end;
    finally
      M.Free;
      Props.Free;
    end;
  end;

begin
  Source := TLandrixXmlXPathTree.Create;
  try
    Source.BeginBuild(True);
    for I := 1 to 100000 do
      Source.BuildStartElement('', '', 'e');
    for I := 1 to 100000 do
      Source.BuildEndElement;
    Source.EndBuild;
    CheckEqualsStr('limit', Run(Strip, 262144), 'stripping white space');
    CheckEqualsStr('limit', Run(CopyOf, 262144), 'copy-of');
{$IFNDEF MSWINDOWS}
    { without a budget only the 8 MB stack of the other platforms holds
      the 10000 levels }
    CheckEqualsStr('limit', Run(CopyOf, 0), 'copy-of without a budget');
{$ENDIF}
    CheckEqualsStr('limit', Serialize('xml'), 'serializing as XML');
    CheckEqualsStr('limit', Serialize('html'), 'serializing as HTML');
  finally
    Source.Free;
  end;
end;

{ MaxStackBytes of the transformer: recursive templates and functions
  against the stack budget (FOER0000, xecLimit); 0 turns it off. }
procedure TestStackBudget;
const
  Sheet1 = '<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"' +
    ' xmlns:f="urn:f" xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="f xs">' +
    '<xsl:output omit-xml-declaration="yes"/><xsl:param name="n" select="50" as="xs:integer"/>' +
    '<xsl:function name="f:down" as="xs:integer"><xsl:param name="k" as="xs:integer"/>' +
    '<xsl:sequence select="if ($k le 0) then 0 else f:down($k - 1) + 1"/></xsl:function>' +
    '<xsl:template match="/"><r><xsl:value-of select="f:down($n)"/>' +
    '<xsl:call-template name="t"><xsl:with-param name="k" select="$n"/></xsl:call-template></r></xsl:template>' +
    '<xsl:template name="t"><xsl:param name="k" as="xs:integer"/>' +
    '<xsl:if test="$k gt 0"><xsl:call-template name="t"><xsl:with-param name="k" select="$k - 1"/>' +
    '</xsl:call-template></xsl:if></xsl:template></xsl:stylesheet>';
var
  Sheet: TLandrixXmlXsltStylesheet;
  T: TLandrixXmlXsltTransformer;
  Source: TLandrixXmlXPathTree;
  Text: string;
  I: Integer;

  function Run: string;
  begin
    try
      Result := LandrixXmlUtf8ToString(T.TransformToUtf8(Source));
    except
      on E: ELandrixXmlXsltError do
        Result := E.XPathCode + ' ' + IntToStr(Ord(E.Code));
    end;
  end;

begin
  Sheet := TLandrixXmlXsltStylesheet.Create;
  Source := TLandrixXmlXPathTree.Create;
  T := nil;
  try
    Sheet.LoadFromUtf8(U(Sheet1), U('urn:test'));
    Source.LoadFromUtf8(U('<doc/>'));
    T := TLandrixXmlXsltTransformer.Create(Sheet);
    CheckEquals(LandrixXmlDefaultMaxStackBytes, T.MaxStackBytes, 'the default budget');
    T.SetParameterXPath(U('n'), U('50'));
    CheckEqualsStr('<r>50</r>', Run, '50 levels');
    T.MaxDepth := 100000;
    T.MaxTemplateDepth := 100000;
    T.MaxStackBytes := 16384;
    T.SetParameterXPath(U('n'), U('100000'));
    CheckEqualsStr('FOER0000 ' + IntToStr(Ord(xecLimit)), Run, 'functions beyond 16 KB of stack');
    T.MaxStackBytes := 1;
    T.SetParameterXPath(U('n'), U('2'));
    CheckEqualsStr('FOER0000 ' + IntToStr(Ord(xecLimit)), Run, 'a budget of one byte');
    T.MaxStackBytes := 0;
    CheckEqualsStr('<r>2</r>', Run, 'no budget');
    { global variables with a sequence constructor that need each other
      nest without a template or function call }
    T.Free;
    T := nil;
    Sheet.Free;
    Sheet := nil;
    Text := '<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"' +
      ' xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="xs">' +
      '<xsl:output omit-xml-declaration="yes"/><xsl:variable name="v100" select="1"/>';
    for I := 99 downto 0 do
      Text := Text + '<xsl:variable name="v' + IntToStr(I) + '" as="xs:integer"><xsl:sequence select="$v' +
        IntToStr(I + 1) + ' + 1"/></xsl:variable>';
    Text := Text + '<xsl:template match="/"><r><xsl:value-of select="$v0"/></r></xsl:template></xsl:stylesheet>';
    Sheet := TLandrixXmlXsltStylesheet.Create;
    Sheet.LoadFromUtf8(U(Text), U('urn:test'));
    T := TLandrixXmlXsltTransformer.Create(Sheet);
    CheckEqualsStr('<r>101</r>', Run, 'nested global variables');
    T.MaxStackBytes := 4096;
    CheckEqualsStr('FOER0000 ' + IntToStr(Ord(xecLimit)), Run, 'nested global variables beyond 4 KB of stack');
    { MaxDepth met in a stylesheet function, raised again with the
      instruction's position: still a limit, which "or" does not hide }
    T.Free;
    T := nil;
    Sheet.Free;
    Sheet := nil;
    Sheet := TLandrixXmlXsltStylesheet.Create;
    Sheet.LoadFromUtf8(U('<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"' +
      ' xmlns:f="urn:f" exclude-result-prefixes="f"><xsl:output omit-xml-declaration="yes"/>' +
      '<xsl:function name="f:inner"><xsl:sequence select="1"/></xsl:function>' +
      '<xsl:function name="f:outer"><xsl:sequence select="f:inner()"/></xsl:function>' +
      '<xsl:template match="/"><r><xsl:value-of select="f:outer() or true()"/></r></xsl:template>' +
      '</xsl:stylesheet>'), U('urn:test'));
    T := TLandrixXmlXsltTransformer.Create(Sheet);
    CheckEqualsStr('<r>true</r>', Run, 'or: functions within MaxDepth');
    T.MaxDepth := 1;
    Text := Run;
    CheckEqualsStr('FOER0000', Copy(Text, 1, 8), 'or: MaxDepth in a stylesheet function (' + Text + ')');
    { the runtime's own MaxTemplateDepth (xecLimit): a limit too }
    T.MaxDepth := 500;
    T.MaxTemplateDepth := 1;
    CheckEqualsStr('FOER0000 ' + IntToStr(Ord(xecLimit)), Run, 'or: MaxTemplateDepth in a stylesheet function');
  finally
    T.Free;
    Source.Free;
    Sheet.Free;
  end;
end;

{ The default stack budget (3/4 of the program's stack on Windows) against
  every kind of recursion, with MaxDepth and MaxTemplateDepth out of the
  way: each stops with FOER0000 (xecLimit) instead of overflowing the
  stack. And the budget of a 1 MB stack holds 200 function levels and 400
  template levels with a literal result element on every toolchain
  (Delphi Win64, where a level takes the most: about 240 and 550). Elsewhere there is no
  default budget, only the depth limits. }
procedure TestStackDefault;
const
  Head = '<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"' +
    ' xmlns:f="urn:f" xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="f xs">' +
    '<xsl:output omit-xml-declaration="yes"/>';
  Down = '<xsl:function name="f:down" as="xs:integer"><xsl:param name="k" as="xs:integer"/>' +
    '<xsl:sequence select="if ($k le 0) then 0 else f:down($k - 1) + 1"/></xsl:function>';
  Tail = '<xsl:function name="f:tail" as="xs:integer"><xsl:param name="k" as="xs:integer"/>' +
    '<xsl:sequence select="if ($k le 0) then 0 else f:tail($k - 1)"/></xsl:function>';
  CallT = '<xsl:template name="t"><xsl:param name="k" as="xs:integer"/><xsl:if test="$k gt 0"><x>' +
    '<xsl:call-template name="t"><xsl:with-param name="k" select="$k - 1"/></xsl:call-template>' +
    '</x></xsl:if></xsl:template>';
  ApplyT = '<xsl:template match="/" mode="m"><xsl:param name="k" as="xs:integer"/><xsl:if test="$k gt 0">' +
    '<xsl:apply-templates select="." mode="m"><xsl:with-param name="k" select="$k - 1"/>' +
    '</xsl:apply-templates></xsl:if></xsl:template>';
  Mixed = '<xsl:function name="f:a"><xsl:param name="k" as="xs:integer"/><xsl:variable name="v">' +
    '<xsl:call-template name="b"><xsl:with-param name="k" select="$k"/></xsl:call-template></xsl:variable>' +
    '<xsl:sequence select="string($v)"/></xsl:function><xsl:template name="b">' +
    '<xsl:param name="k" as="xs:integer"/><xsl:value-of select="if ($k le 0) then 0 else f:a($k - 1)"/>' +
    '</xsl:template>';
  Pred = '<xsl:function name="f:p" as="xs:integer"><xsl:param name="k" as="xs:integer"/>' +
    '<xsl:sequence select="if ($k le 0) then 0 else count((1, 2)[f:p($k - 1) ge 0])"/></xsl:function>';
  SortKey = '<xsl:function name="f:s"><xsl:param name="k" as="xs:integer"/><xsl:choose>' +
    '<xsl:when test="$k le 0"><xsl:sequence select="0"/></xsl:when><xsl:otherwise>' +
    '<xsl:perform-sort select="(1, 2)"><xsl:sort select="f:s($k - 1)"/></xsl:perform-sort>' +
    '</xsl:otherwise></xsl:choose></xsl:function>';
  Group = '<xsl:function name="f:g"><xsl:param name="k" as="xs:integer"/><xsl:choose>' +
    '<xsl:when test="$k le 0"><xsl:sequence select="0"/></xsl:when><xsl:otherwise>' +
    '<xsl:for-each-group select="(1, 2)" group-by="f:g($k - 1)">' +
    '<xsl:sequence select="current-grouping-key()"/></xsl:for-each-group></xsl:otherwise></xsl:choose>' +
    '</xsl:function>';
  Avt = '<xsl:function name="f:v"><xsl:param name="k" as="xs:integer"/><xsl:variable name="e">' +
    '<x a="{if ($k le 0) then 0 else f:v($k - 1)}"/></xsl:variable><xsl:sequence select="string($e/x/@a)"/>' +
    '</xsl:function>';
  Build = '<xsl:function name="f:e"><xsl:param name="k" as="xs:integer"/><e><xsl:if test="$k gt 0">' +
    '<xsl:sequence select="f:e($k - 1)"/></xsl:if></e></xsl:function>';
  Analyze = '<xsl:function name="f:r"><xsl:param name="k" as="xs:integer"/><xsl:choose>' +
    '<xsl:when test="$k le 0"><xsl:sequence select="0"/></xsl:when><xsl:otherwise>' +
    '<xsl:analyze-string select="''a''" regex="a"><xsl:matching-substring>' +
    '<xsl:sequence select="f:r($k - 1)"/></xsl:matching-substring></xsl:analyze-string>' +
    '</xsl:otherwise></xsl:choose></xsl:function>';
  Deep = '100000000';
var
  Source: TLandrixXmlXPathTree;

  function Run(const Decl, Start: string; Unlimited: Boolean): string;
  var
    Sheet: TLandrixXmlXsltStylesheet;
    T: TLandrixXmlXsltTransformer;
  begin
    Sheet := TLandrixXmlXsltStylesheet.Create;
    T := nil;
    try
      Sheet.LoadFromUtf8(U(Head + Decl + '<xsl:template match="/"><r>' + Start + '</r></xsl:template>' +
        '</xsl:stylesheet>'), U('urn:test'));
      T := TLandrixXmlXsltTransformer.Create(Sheet);
      if Unlimited then
      begin
        T.MaxDepth := MaxInt;
        T.MaxTemplateDepth := MaxInt;
      end;
      try
        Result := LandrixXmlUtf8ToString(T.TransformToUtf8(Source));
      except
        on E: ELandrixXmlError do
          { the stack budget, not another limit }
          if (E.Code = xecLimit) and (E is ELandrixXmlXPathError) and
            (ELandrixXmlXPathError(E).XPathCode = 'FOER0000') and (Pos('bytes of stack', E.Message) > 0) then
            Result := 'limit'
          else
            Result := E.Message;
      end;
    finally
      T.Free;
      Sheet.Free;
    end;
  end;

  procedure Limit(const Decl, Start, What: string);
  begin
    CheckEqualsStr('limit', Run(Decl, Start, True), What);
  end;

begin
  Source := TLandrixXmlXPathTree.Create;
  try
    Source.LoadFromUtf8(U('<doc/>'));
    CheckEqualsStr('<r>200</r>', Run(Down, '<xsl:value-of select="f:down(200)"/>', False),
      '200 function levels with the defaults');
    CheckEqualsStr('<r>400</r>', Run(CallT, '<xsl:variable name="v"><xsl:call-template name="t">' +
      '<xsl:with-param name="k" select="400"/></xsl:call-template></xsl:variable>' +
      '<xsl:value-of select="count($v//x)"/>', False), '400 template levels with the defaults');
    if LandrixXmlDefaultMaxStackBytes > 0 then
    begin
      Limit(Down, '<xsl:value-of select="f:down(' + Deep + ')"/>', 'a function');
      Limit(Tail, '<xsl:value-of select="f:tail(' + Deep + ')"/>', 'a tail call');
      Limit(CallT, '<xsl:call-template name="t"><xsl:with-param name="k" select="' + Deep + '"/>' +
        '</xsl:call-template>', 'call-template');
      Limit(ApplyT, '<xsl:apply-templates select="." mode="m"><xsl:with-param name="k" select="' + Deep + '"/>' +
        '</xsl:apply-templates>', 'apply-templates');
      Limit(Mixed, '<xsl:value-of select="f:a(' + Deep + ')"/>', 'a function through a template');
      Limit(Pred, '<xsl:value-of select="f:p(' + Deep + ')"/>', 'a function in a predicate');
      Limit(SortKey, '<xsl:value-of select="f:s(' + Deep + ')"/>', 'a sort key');
      Limit(Group, '<xsl:value-of select="f:g(' + Deep + ')"/>', 'a grouping key');
      Limit(Avt, '<xsl:value-of select="f:v(' + Deep + ')"/>', 'an attribute value template');
      Limit(Build, '<xsl:value-of select="count(f:e(' + Deep + ')//*)"/>', 'a growing result tree');
      Limit(Analyze, '<xsl:value-of select="f:r(' + Deep + ')"/>', 'analyze-string');
    end;
  finally
    Source.Free;
  end;
end;

{ file: URIs of the default resolver: an empty host and localhost are the
  local machine; another host is no file (neither the local path without
  the host nor a UNC path). }
procedure TestFileUris;
begin
  CheckEqualsStr('', LandrixXmlXsltUriToFileName('http://x/a.xsl'), 'not a file URI');
  {$IFDEF MSWINDOWS}
  CheckEqualsStr('D:\x\a b.xsl', LandrixXmlXsltUriToFileName('file:///D:/x/a%20b.xsl'), 'empty host');
  CheckEqualsStr('D:\x\a.xsl', LandrixXmlXsltUriToFileName('file://localhost/D:/x/a.xsl'), 'localhost');
  CheckEqualsStr('D:\x\a.xsl', LandrixXmlXsltUriToFileName('file:/D:/x/a.xsl'), 'no authority');
  CheckEqualsStr('', LandrixXmlXsltUriToFileName('file://server/share/rules.xsl'), 'other host');
  {$ELSE}
  CheckEqualsStr('/x/a.xsl', LandrixXmlXsltUriToFileName('file:///x/a.xsl'), 'empty host');
  CheckEqualsStr('/x/a.xsl', LandrixXmlXsltUriToFileName('file://LocalHost/x/a.xsl'), 'localhost');
  CheckEqualsStr('', LandrixXmlXsltUriToFileName('file://server/share/rules.xsl'), 'other host');
  {$ENDIF}
end;

{ Copying an element with many attributes (the duplicate check by hash)
  and many namespace declarations (sorted for the output). }
procedure TestManyAttributesCopy;
var
  Sheet: TLandrixXmlXsltStylesheet;
  T: TLandrixXmlXsltTransformer;
  Source: TLandrixXmlXPathTree;
  Xml, Expected, Output, Rest: TLandrixXmlUtf8;
  I: Integer;
begin
  Sheet := TLandrixXmlXsltStylesheet.Create;
  T := nil;
  Source := TLandrixXmlXPathTree.Create;
  try
    Sheet.LoadFromUtf8(U(
      '<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">' +
      '<xsl:output omit-xml-declaration="yes"/>' +
      '<xsl:template match="/"><out><xsl:copy-of select="r/@*"/>' +
      '<xsl:attribute name="a5">x</xsl:attribute><xsl:attribute name="a39">y</xsl:attribute>' +
      '</out><xsl:copy-of select="r"/>' +
      '<dup><xsl:copy-of select="r/@*"/><xsl:attribute name="q:a5" namespace="urn:q">z</xsl:attribute></dup>' +
      '</xsl:template>' +
      '</xsl:stylesheet>'), U('urn:test'));
    Xml := U('<r');
    Expected := U('<out');
    for I := 0 to 39 do
    begin
      Xml := Xml + U(' a' + IntToStr(I) + '="' + IntToStr(I) + '"');
      if I = 5 then
        Expected := Expected + U(' a5="x"')
      else if I = 39 then
        Expected := Expected + U(' a39="y"')
      else
        Expected := Expected + U(' a' + IntToStr(I) + '="' + IntToStr(I) + '"');
    end;
    for I := 0 to 39 do
      Xml := Xml + U(' xmlns:p' + IntToStr(I) + '="u' + IntToStr(I) + '"');
    Xml := Xml + U('/>');
    Source.LoadFromUtf8(Xml);
    T := TLandrixXmlXsltTransformer.Create(Sheet);
    Output := T.TransformToUtf8(Source);
    CheckEqualsUtf8(Expected + U('/>'), Copy(Output, 1, Length(Expected) + 2),
      'replaced attributes keep their place');
    { the copy of r: every declaration (sorted) and every attribute }
    Rest := Copy(Output, Length(Expected) + 3, MaxInt);
    Rest := Copy(Rest, 1, Pos(U('<dup'), Rest) - 1);
    for I := 0 to 39 do
    begin
      Check(Pos(U(' xmlns:p' + IntToStr(I) + '="u' + IntToStr(I) + '"'), Rest) > 0,
        'declaration p' + IntToStr(I) + ' on the copy of r');
      Check(Pos(U(' a' + IntToStr(I) + '="' + IntToStr(I) + '"'), Rest) > 0,
        'attribute a' + IntToStr(I) + ' on the copy of r');
    end;
    Check(Pos(U('xmlns:p1="u1"'), Rest) < Pos(U('xmlns:p10="u10"'), Rest), 'p1 before p10');
    Check(Pos(U('xmlns:p10="u10"'), Rest) < Pos(U('xmlns:p2="u2"'), Rest), 'p10 before p2');
    Check(Pos(U('xmlns:p39="u39"'), Rest) < Pos(U('xmlns:p4="u4"'), Rest), 'p39 before p4');
    { the same local name in another namespace is another attribute }
    Rest := Copy(Output, Pos(U('<dup'), Output), MaxInt);
    Check(Pos(U(' a5="5"'), Rest) > 0, 'a5 kept next to q:a5');
    Check(Pos(U(' q:a5="z"'), Rest) > 0, 'q:a5 added');
  finally
    T.Free;
    Source.Free;
    Sheet.Free;
  end;
end;

const
  ReviewHead = '<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"' +
    ' xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="xs">' +
    '<xsl:output omit-xml-declaration="yes"/>' +
    '<xsl:key name="g" match="s" use="count(current-group())"/>' +
    '<xsl:key name="d" match="s" use="(xs:dayTimeDuration(''P1D''), xs:dayTimeDuration(''P2D''))"/>' +
    '<xsl:key name="i" match="s" use="xs:integer(''9007199254740993'')"/>';

{ The output of the template body Body on <s/> (a stylesheet at
  file:///s/t.xsl, documents a.xml and b.xml beside it, gone.xml an alias
  of a file that is not there), or the error code. }
function RunReviewSheet(const Body: string): string;
var
  Sheet: TLandrixXmlXsltStylesheet;
  T: TLandrixXmlXsltTransformer;
  Source: TLandrixXmlXPathTree;
  Resolver: TLandrixXmlXsltResolver;
begin
  Sheet := TLandrixXmlXsltStylesheet.Create;
  Source := TLandrixXmlXPathTree.Create;
  Resolver := TLandrixXmlXsltResolver.Create;
  T := nil;
  try
    try
      Sheet.LoadFromUtf8(U(ReviewHead + '<xsl:template match="/"><r>' + Body +
        '</r></xsl:template></xsl:stylesheet>'), U('file:///s/t.xsl'));
      Resolver.AddUtf8(U('file:///s/a.xml'), U('<a/>'));
      Resolver.AddUtf8(U('file:///s/b.xml'), U('<b/>'));
      Resolver.AddFile(U('file:///s/gone.xml'), DataFolder + 'no-such-file.xml');
      Source.LoadFromUtf8(U('<s/>'));
      T := TLandrixXmlXsltTransformer.Create(Sheet);
      T.Resolver := Resolver;
      Result := LandrixXmlUtf8ToString(T.TransformToUtf8(Source));
    except
      on E: ELandrixXmlXPathError do
        Result := E.XPathCode;
    end;
  finally
    T.Free;
    Resolver.Free;
    Source.Free;
    Sheet.Free;
  end;
end;

{ The serialized result of a stylesheet with Output (an xsl:output
  element) and a template for / with Body; Param is bound to $p. The
  error code on a dynamic or serialization error. }
function RunOutputSheet(const Output, Body: string; const Param: TLandrixXmlUtf8): string;
var
  Sheet: TLandrixXmlXsltStylesheet;
  T: TLandrixXmlXsltTransformer;
  Source: TLandrixXmlXPathTree;
  Stream: TMemoryStream;
  S: TLandrixXmlUtf8;
begin
  Sheet := TLandrixXmlXsltStylesheet.Create;
  Source := TLandrixXmlXPathTree.Create;
  Stream := TMemoryStream.Create;
  T := nil;
  try
    try
      Sheet.LoadFromUtf8(U('<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">' +
        Output + '<xsl:param name="p" select="''''"/><xsl:template match="/">' + Body +
        '</xsl:template></xsl:stylesheet>'), U('file:///s/t.xsl'));
      Source.LoadFromUtf8(U('<s/>'));
      T := TLandrixXmlXsltTransformer.Create(Sheet);
      T.SetParameter(U('p'), Param);
      T.Transform(Source, Stream);
      S := '';
      SetLength(S, Integer(Stream.Size));
      if Length(S) > 0 then
        Move(Stream.Memory^, S[1], Length(S));
      Result := LandrixXmlUtf8ToString(S);
    except
      on E: ELandrixXmlXPathError do
        Result := E.XPathCode;
    end;
  finally
    T.Free;
    Stream.Free;
    Source.Free;
    Sheet.Free;
  end;
end;

{ The error code of compiling Main (file:///s/main.xsl) with the module
  Imp at file:///s/imp.xsl, 'ok' if it compiles. }
function CompileCode(const Main, Imp: string): string;
var
  Sheet: TLandrixXmlXsltStylesheet;
  Resolver: TLandrixXmlXsltResolver;
begin
  Sheet := TLandrixXmlXsltStylesheet.Create;
  Resolver := TLandrixXmlXsltResolver.Create;
  try
    try
      Resolver.AddUtf8(U('file:///s/imp.xsl'), U(Imp));
      Sheet.LoadFromUtf8(U(Main), U('file:///s/main.xsl'), Resolver);
      Result := 'ok';
    except
      on E: ELandrixXmlXPathError do
        Result := E.XPathCode;
    end;
  finally
    Resolver.Free;
    Sheet.Free;
  end;
end;

{ Static errors Saxon reports: unknown attributes (XTSE0090, XTSE0805),
  undeclared prefixes in exclude-result-prefixes (XTSE0808, XTSE0809)
  and the current group in a pattern (XTSE1060, XTSE1070). }
procedure TestStaticErrors;
const
  Head = '<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">';
  Tail = '</xsl:stylesheet>';
begin
  CheckEqualsStr('XTSE0090', CompileCode(Head + '<xsl:template match="/"><xsl:value-of selct="1"/>' +
    '</xsl:template>' + Tail, ''), 'an unknown attribute of xsl:value-of');
  CheckEqualsStr('ok', CompileCode(Head + '<xsl:template match="/"><xsl:value-of select="1" ' +
    'use-when="true()" xpath-default-namespace="urn:x"/></xsl:template>' + Tail, ''), 'standard attributes');
  CheckEqualsStr('ok', CompileCode('<xsl:stylesheet version="4.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">' +
    '<xsl:template match="/"><xsl:value-of select="1" new-attribute="x"/></xsl:template>' + Tail, ''),
    'forwards compatible processing ignores it');
  CheckEqualsStr('XTSE0805', CompileCode(Head + '<xsl:template match="/"><r xsl:foo="1"/></xsl:template>' + Tail,
    ''), 'an unknown xsl:attribute of a literal result element');
  CheckEqualsStr('ok', CompileCode(Head + '<xsl:template match="/"><r xsl:use-attribute-sets="" ' +
    'xsl:exclude-result-prefixes="#all"/></xsl:template>' + Tail, ''), 'xsl:attributes of a literal result element');
  CheckEqualsStr('XTSE0808', CompileCode('<xsl:stylesheet version="2.0" ' +
    'xmlns:xsl="http://www.w3.org/1999/XSL/Transform" exclude-result-prefixes="p"/>', ''), 'an undeclared prefix');
  CheckEqualsStr('XTSE0809', CompileCode('<xsl:stylesheet version="2.0" ' +
    'xmlns:xsl="http://www.w3.org/1999/XSL/Transform" exclude-result-prefixes="#default"/>', ''),
    '#default without a default namespace');
  CheckEqualsStr('ok', CompileCode('<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" ' +
    'xmlns:p="urn:p" exclude-result-prefixes="p"/>', ''), 'a declared prefix');
  CheckEqualsStr('XTSE0020', CompileCode('<xsl:stylesheet version="2.0" ' +
    'xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:p="urn:p" exclude-result-prefixes="p #all"/>', ''),
    '#all with another prefix');
  CheckEqualsStr('XTSE0808', CompileCode(Head + '<xsl:template name="t" version="4.0" ' +
    'exclude-result-prefixes="missing"/>' + Tail, ''), 'an undeclared prefix in forwards compatible processing');
  CheckEqualsStr('ok', CompileCode('<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" ' +
    'xmlns:p="urn:p"><p:data xsl:unknown="1" xsl:exclude-result-prefixes="missing"/>' + Tail, ''),
    'xsl: attributes of a data element');
  CheckEqualsStr('XTSE1060', CompileCode(Head + '<xsl:template match="a[current-group()]"/>' + Tail, ''),
    'current-group() in a pattern');
  CheckEqualsStr('XTSE1070', CompileCode(Head + '<xsl:key name="k" match="a[fn:current-grouping-key()]" ' +
    'use="." xmlns:fn="http://www.w3.org/2005/xpath-functions"/>' + Tail, ''), 'current-grouping-key() in a pattern');
  CheckEqualsStr('ok', CompileCode(Head + '<xsl:template match="a[. = ''current-group()'']"/>' + Tail, ''),
    'the name in a string literal');
  CheckEqualsStr('ok', CompileCode(Head + '<xsl:template match="a[(: current-group() :) true()]"/>' + Tail, ''),
    'the name in a comment');
  CheckEqualsStr('ok', CompileCode('<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" ' +
    'xmlns:my="urn:my"><xsl:function name="my:current-group"><xsl:sequence select="1"/></xsl:function>' +
    '<xsl:template match="a[my:current-group()]"/>' + Tail, ''), 'a function of another namespace');
end;

{ Static checks from the review of the compiler (Saxon HE 12.9). }
procedure TestCompilerReviewEdges;
const
  Head = '<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">';
  Tail = '</xsl:stylesheet>';
begin
  CheckEqualsStr('XTSE0550', CompileCode(Head + '<xsl:template match="a" mode="#all #default"/>' + Tail, ''),
    'mode #all with another');
  CheckEqualsStr('XTSE0550', CompileCode(Head + '<xsl:template match="a" mode="m m"/>' + Tail, ''),
    'a mode twice');
  CheckEqualsStr('XTSE0550', CompileCode(Head + '<xsl:template match="a" mode="#current"/>' + Tail, ''),
    'mode #current');
  CheckEqualsStr('ok', CompileCode(Head + '<xsl:template match="a" mode="m #default"/>' + Tail, ''),
    'two modes');
  CheckEqualsStr('XTSE0550', CompileCode(Head + '<xsl:template match="a" mode="name!1223"/>' + Tail, ''),
    'a mode that is no QName');
  CheckEqualsStr('ok', CompileCode(Head + '<xsl:template match="a" mode="#unnamed"/>' + Tail, ''),
    'mode #unnamed (Saxon)');
  CheckEqualsStr('XTSE0340', CompileCode(Head + '<xsl:template match=""/>' + Tail, ''), 'an empty match');
  { pattern steps as Saxon checks them (XSLT 3.0 rules) }
  CheckEqualsStr('XTSE0340', CompileCode(Head + '<xsl:template match="name/1223"/>' + Tail, ''),
    'a number as a step');
  CheckEqualsStr('XTSE0340', CompileCode(Head + '<xsl:template match="a/string()"/>' + Tail, ''),
    'a function as a step');
  CheckEqualsStr('XTSE0340', CompileCode(Head + '<xsl:template match="a/.."/>' + Tail, ''), 'the parent axis');
  CheckEqualsStr('XTSE0340', CompileCode(Head + '<xsl:variable name="v" select="/"/>' +
    '<xsl:template match="a/$v"/>' + Tail, ''), 'a variable after the start');
  CheckEqualsStr('XTSE0340', CompileCode(Head + '<xsl:template match="//id(''x'')"/>' + Tail, ''),
    'id() after //');
  CheckEqualsStr('XTSE0340', CompileCode(Head + '<xsl:key name="k" match="a/(b, c)" use="."/>' +
    '<xsl:template match="/"/>' + Tail, ''), 'a sequence in a key pattern');
  CheckEqualsStr('ok', CompileCode(Head + '<xsl:variable name="v" select="/"/>' +
    '<xsl:template match="$v[1]//b | a/(b|c)/self::c | a/. | root()/a | id(''x'')//b | $v intersect b | ' +
    'root() except b | key(''k'', $v) | id($v)"/><xsl:key name="k" match="b" use="."/>' + Tail, ''),
    'patterns Saxon accepts');
  CheckEqualsStr('ok', CompileCode(Head + '<xsl:template match=".[1]"/>' + Tail, ''), '. as the pattern');
  CheckEqualsStr('ok', CompileCode(Head + '<xsl:template match="(.)/b"/>' + Tail, ''), '(.) as the first step');
  CheckEqualsStr('XTSE0340', CompileCode(Head + '<xsl:template match="a | ."/>' + Tail, ''), '. as a branch');
  CheckEqualsStr('XTSE0340', CompileCode(Head + '<xsl:template match="./b"/>' + Tail, ''), '. as the first step');
  CheckEqualsStr('XTSE0340', CompileCode(Head + '<xsl:template match="a/(/b)"/>' + Tail, ''), '/ after a step');
  CheckEqualsStr('XTSE0340', CompileCode(Head + '<xsl:template match="id(@id)"/>' + Tail, ''),
    'a path as the argument of id()');
  { XSLT predeclares neither xs nor fn (Saxon: namespace-6202) }
  CheckEqualsStr('XPST0081', CompileCode(Head + '<xsl:template match="/"><xsl:value-of select="xs:integer(1)"/>' +
    '</xsl:template>' + Tail, ''), 'xs without a declaration');
  CheckEqualsStr('XPST0081', CompileCode(Head + '<xsl:variable name="v" as="xs:integer" select="1"/>' +
    '<xsl:template match="/"/>' + Tail, ''), 'xs in a type without a declaration');
  CheckEqualsStr('XPST0081', CompileCode(Head + '<xsl:template match="/" use-when="fn:true()"/>' + Tail, ''),
    'fn in use-when without a declaration');
  CheckEqualsStr('ok', CompileCode(Head + '<xsl:template match="/"><xsl:value-of xmlns:xs="' +
    'http://www.w3.org/2001/XMLSchema" xmlns:fn="http://www.w3.org/2005/xpath-functions" ' +
    'select="fn:string(xs:integer(1))"/></xsl:template>' + Tail, ''), 'xs and fn declared');
  { a priority of more than 255 characters (FPC's Val refused it) }
  CheckEqualsStr('ok', CompileCode(Head + '<xsl:template match="a" priority="0.' + StringOfChar('0', 300) +
    '1"/>' + Tail, ''), 'a long priority');
  CheckEqualsStr('XTSE0010', CompileCode(Head + '<xsl:include href="imp.xsl"/>' + Tail,
    '<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"/>'), 'an included module without version');
  CheckEqualsStr('ok', CompileCode(Head + '<m:data xmlns:m="urn:m"><xsl:element name="x" type="any"/></m:data>' +
    '<xsl:template match="/"/>' + Tail, ''), 'a user-defined data element');
  { two of the same precedence, overridden by the importing module }
  CheckEqualsStr('ok', CompileCode(Head + '<xsl:import href="imp.xsl"/><xsl:variable name="x" select="3"/>' +
    '<xsl:template name="t"/>' + Tail, Head + '<xsl:variable name="x" select="1"/>' +
    '<xsl:variable name="x" select="2"/><xsl:template name="t"/><xsl:template name="t"/>' + Tail),
    'duplicates overridden');
  CheckEqualsStr('XTSE0630', CompileCode(Head + '<xsl:import href="imp.xsl"/>' + Tail, Head +
    '<xsl:variable name="x" select="1"/><xsl:variable name="x" select="2"/>' + Tail), 'duplicate variables');
  CheckEqualsStr('XTSE0660', CompileCode(Head + '<xsl:import href="imp.xsl"/>' + Tail, Head +
    '<xsl:template name="t"/><xsl:template name="t"/>' + Tail), 'duplicate templates');
  { a comment does not change the default priority of a name test (0):
    the rule with priority 0.25 wins }
  CheckEqualsStr('<r>b</r>', RunOutputSheet('<xsl:output method="xml" omit-xml-declaration="yes"/>' +
    '<xsl:template match="s (: a comment :)"><r>a</r></xsl:template>' +
    '<xsl:template match="s" priority="0.25"><r>b</r></xsl:template>', '<xsl:apply-templates/>', ''),
    'a comment in a pattern');
  CheckEqualsStr('<r>b</r>', RunOutputSheet('<xsl:output method="xml" omit-xml-declaration="yes"/>' +
    '<xsl:template match="x (: don''t :) | s"><r>a</r></xsl:template>' +
    '<xsl:template match="s" priority="0.25"><r>b</r></xsl:template>', '<xsl:apply-templates/>', ''),
    'a quote in a comment of a pattern');
end;

{ Serialization edges from the review (Saxon HE 12.9). }
procedure TestOutputReviewEdges;
var
  Long: string;
  I: Integer;
  R: string;
begin
  { script and style: a character the encoding lacks is a reference }
  R := RunOutputSheet('<xsl:output method="html" encoding="US-ASCII"/>',
    '<html><script>let x="&#233;"</script></html>', '');
  Check(Pos('<script>let x="&#xe9;"</script>', R) > 0, 'script in US-ASCII: ' + R);
  { a C0 control from a parameter: a character reference }
  CheckEqualsStr('<r>&#x1;</r>', RunOutputSheet('<xsl:output method="xml" omit-xml-declaration="yes"/>',
    '<r><xsl:value-of select="$p"/></r>', #1), 'U+0001 from a parameter');
  CheckEqualsStr('SEPM0010', RunOutputSheet('<xsl:output method="xml" undeclare-prefixes="yes" ' +
    'omit-xml-declaration="yes" standalone="yes"/>', '<r/>', ''), 'SEPM0010 first');
  CheckEqualsStr('SEPM0010', RunOutputSheet('<xsl:output method="xml" undeclare-prefixes="yes"/>', '<r/>', ''),
    'undeclare-prefixes with XML 1.0');
  CheckEqualsStr('SEPM0009', RunOutputSheet('<xsl:output method="xml" omit-xml-declaration="yes" ' +
    'standalone="no"/>', '<r/>', ''), 'standalone without declaration');
  R := RunOutputSheet('<xsl:output method="xml" encoding="utf8"/>', '<r/>', '');
  CheckEqualsStr('<?xml version="1.0" encoding="UTF-8"?>', Copy(R, 1, 38), 'utf8 named UTF-8');
  { many character references in one text node (linear time) }
  Long := '';
  for I := 1 to 20000 do
    Long := Long + '&#233;';
  R := RunOutputSheet('<xsl:output method="xml" encoding="US-ASCII" omit-xml-declaration="yes"/>',
    '<r>' + Long + '</r>', '');
  CheckEquals(7 + 20000 * 6, Length(R), 'references in US-ASCII');
end;

{ Edge cases from the review of the XSLT runtime (expected values as
  Saxon HE 12). }
procedure TestRuntimeReviewEdges;
var
  Sheet: TLandrixXmlXsltStylesheet;
  T: TLandrixXmlXsltTransformer;
  Source, Param, Target: TLandrixXmlXPathTree;
  Code: string;
begin
  { a constructed xml:id has its white space collapsed (literal, AVT,
    xsl:attribute, also without an element), the AVT of the stylesheet is
    evaluated as written (Saxon) }
  CheckEqualsStr('<r>[p q][g h][i j]<x xml:id="id4"/></r>', RunReviewSheet('<xsl:variable name="t">' +
    '<x xml:id="  p  q  "/></xsl:variable>[<xsl:value-of select="$t/x/@xml:id"/>]' +
    '<xsl:variable name="a" as="attribute()"><xsl:attribute name="xml:id">&#9;g&#9;&#9;h&#10;' +
    '</xsl:attribute></xsl:variable>[<xsl:value-of select="$a"/>]' +
    '<xsl:variable name="u"><y xml:id="{''i&#9;&#9;j''}"/></xsl:variable>[<xsl:value-of select="$u/y/@xml:id"/>]' +
    '<x xml:id="id{string-length(''a  b'')}"/>'), 'xml:id');
  { a resource that cannot be opened is not available }
  CheckEqualsStr('<r>false</r>', RunReviewSheet('<xsl:value-of select="doc-available(''gone.xml'')"/>'),
    'doc-available() of a file that cannot be opened');
  CheckEqualsStr('FODC0002', RunReviewSheet('<xsl:value-of select="doc(''gone.xml'')"/>'),
    'doc() of a file that cannot be opened');
  CheckEqualsStr('<r>false</r>', RunReviewSheet(
    '<xsl:value-of select="unparsed-text-available(''gone.xml'')"/>'),
    'unparsed-text-available() of a file that cannot be opened');
  CheckEqualsStr('<r>a</r>', RunReviewSheet('<xsl:variable name="t"><xsl:text>a.xml</xsl:text>' +
    '</xsl:variable><xsl:value-of select="name(document($t/text())/*)"/>'),
    'document() of a text node in a temporary tree');
  { document(): document order (the order the documents were read in) }
  CheckEqualsStr('<r>b ba true</r>', RunReviewSheet('<xsl:value-of select="name(doc(''b.xml'')/*), ' +
    'string-join(for $d in document((''a.xml'', ''b.xml'', ''a.xml'')) return name($d/*), ''''), ' +
    'document((''a.xml'', ''b.xml''))[1] is document((''b.xml'', ''a.xml''))[1]"/>'),
    'document() in document order');
  { white space around computed names and yes/no values }
  CheckEqualsStr('<r><e a="1"/></r>', RunReviewSheet('<xsl:element name=" {''e''} "><xsl:attribute name="a ">1' +
    '</xsl:attribute></xsl:element>'), 'white space around a computed name');
  CheckEqualsStr('XTMM9000', RunReviewSheet('<xsl:message terminate="{'' yes ''}">m</xsl:message>'),
    'terminate with white space');
  CheckEqualsStr('XTDE0030', RunReviewSheet('<xsl:message terminate="{''maybe''}"><xsl:message' +
    ' terminate="yes">inner</xsl:message></xsl:message>'), 'terminate neither yes nor no, before the content');
  CheckEqualsStr('XTSE0020', RunReviewSheet('<xsl:if test="false()"><xsl:message terminate="maybe">m' +
    '</xsl:message></xsl:if>'), 'a fixed terminate neither yes nor no');
  CheckEqualsStr('<r>12,345</r>', RunReviewSheet('<xsl:number value="12345" grouping-separator=","' +
    ' grouping-size="+3"/>'), 'a grouping size with a plus sign');
  CheckEqualsStr('XTDE0030', RunReviewSheet('<xsl:number value="12345" grouping-separator=","' +
    ' grouping-size="+2147483648"/>'), 'a grouping size beyond 32 bits');
  { level="single" with from: an ancestor-or-self of the counted node must
    match from (Saxon; no root fallback) }
  CheckEqualsStr('<r>[][1][1]</r>', RunReviewSheet('<xsl:for-each select="/s"><xsl:text>[</xsl:text>' +
    '<xsl:number count="s" from="p"/><xsl:text>][</xsl:text><xsl:number count="s" from="s"/>' +
    '<xsl:text>][</xsl:text><xsl:number from="p"/><xsl:text>]</xsl:text></xsl:for-each>'),
    'xsl:number level="single" with from');
  CheckEqualsStr('<r>3000 1</r>', RunReviewSheet('<xsl:variable name="g">' +
    '<xsl:for-each-group select="for $i in 1 to 3000 return xs:integer(''1000000000000000000000000'') + $i"' +
    ' group-by=".">g</xsl:for-each-group></xsl:variable><xsl:value-of select="string-length($g), ' +
    'count(distinct-values(for $i in 1 to 3 return xs:integer(''1000000000000000000000000'') + $i))' +
    ' - 2"/>'), 'many integers with one double');
  { grouping: integers and decimals exactly unless they are the same as
    their double (key(): as doubles); durations equal across their types }
  CheckEqualsStr('<r>gg|gg|g|g|gg|gg|ggg</r>', RunReviewSheet(
    '<xsl:for-each-group select="(xs:integer(''9007199254740993''), xs:integer(''9007199254740992''))"' +
    ' group-by=".">g</xsl:for-each-group>|' +
    '<xsl:for-each-group select="(xs:decimal(''0.1000000000000000000001''), xs:decimal(''0.1''))"' +
    ' group-by=".">g</xsl:for-each-group>|' +
    '<xsl:for-each-group select="(1, 1e0)" group-by=".">g</xsl:for-each-group>|' +
    '<xsl:for-each-group select="(0.1, 0.1e0)" group-by=".">g</xsl:for-each-group>|' +
    '<xsl:for-each-group select="(0.1000000000000000000001, 0.1e0, 0.1)" group-by=".">g</xsl:for-each-group>|' +
    '<xsl:for-each-group select="(1, 1, 1e0, 2)" group-adjacent=".">g</xsl:for-each-group>|' +
    '<xsl:for-each-group select="(xs:duration(''P1D''), xs:dayTimeDuration(''PT24H''),' +
    ' xs:yearMonthDuration(''P12M''), xs:duration(''P1Y''), xs:yearMonthDuration(''P0M''),' +
    ' xs:dayTimeDuration(''PT0S''))" group-by=".">g</xsl:for-each-group>'), 'grouping keys');
  CheckEqualsStr('<r>1 1 1</r>', RunReviewSheet('<xsl:value-of select="count(key(''d'', xs:duration(''P1D''))), ' +
    'count(key(''i'', xs:integer(''9007199254740992''))), count(key(''i'', xs:integer(''9007199254740993'')))"/>'),
    'key values');
  CheckEqualsStr('XTDE1061', RunReviewSheet('<xsl:for-each-group select="/*" group-by="1">' +
    '<xsl:value-of select="count(key(''g'', 1))"/></xsl:for-each-group>'), 'current-group() in a key');
  { generate-id(): a parentless attribute; ids kept across trees }
  CheckEqualsStr('<r>true 2</r>', RunReviewSheet('<xsl:variable name="a" as="attribute()">' +
    '<xsl:attribute name="x">1</xsl:attribute></xsl:variable>' +
    '<xsl:value-of select="string-length(generate-id($a)) gt 0, count(distinct-values(' +
    'for $i in 1 to 3 return (generate-id(/s), generate-id(doc(''a.xml'')/a))))"/>'), 'generate-id()');
  Sheet := TLandrixXmlXsltStylesheet.Create;
  Source := TLandrixXmlXPathTree.Create;
  Param := TLandrixXmlXPathTree.Create;
  Target := TLandrixXmlXPathTree.Create;
  T := nil;
  try
    Sheet.LoadFromUtf8(U(ReviewHead + '<xsl:param name="p"/><xsl:param name="q"/>' +
      '<xsl:template match="/"><r><xsl:value-of select="$p is $q, count($p | $q)"/></r></xsl:template>' +
      '<xsl:template name="main"><xsl:result-document><ok/></xsl:result-document>' +
      '<xsl:sequence select="''''"/></xsl:template>' +
      '<xsl:template name="text"><xsl:value-of select="''''"/><xsl:result-document><ok/></xsl:result-document>' +
      '</xsl:template></xsl:stylesheet>'), U('file:///s/t.xsl'));
    Source.LoadFromUtf8(U('<s/>'));
    Param.LoadFromUtf8(U('<p/>'));
    T := TLandrixXmlXsltTransformer.Create(Sheet);
    { one tree given for two parameters: the same nodes }
    T.SetParameterTree(U('p'), Param);
    T.SetParameterTree(U('q'), Param);
    CheckEqualsUtf8(U('<r>true 1</r>'), T.TransformToUtf8(Source), 'one tree for two parameters');
    { the implicit principal result has the base output URI }
    T.BaseOutputUri := U('file:///out/main.xml');
    T.TransformToTree(Source, Target);
    CheckEqualsUtf8(U('file:///out/main.xml'), Target.BaseUri, 'the base URI of the implicit result');
    { an empty string besides xsl:result-document is a principal result too }
    T.InitialTemplate := U('main');
    Code := 'none';
    try
      T.TransformToUtf8(nil);
    except
      on E: ELandrixXmlXsltError do
        Code := E.XPathCode;
    end;
    CheckEqualsStr('XTDE1490', Code, 'an empty string besides xsl:result-document');
    T.InitialTemplate := U('text');
    Code := 'none';
    try
      T.TransformToUtf8(nil);
    except
      on E: ELandrixXmlXsltError do
        Code := E.XPathCode;
    end;
    CheckEqualsStr('XTDE1490', Code, 'an empty text node before xsl:result-document');
  finally
    T.Free;
    Target.Free;
    Param.Free;
    Source.Free;
    Sheet.Free;
  end;
end;

{ the initial mode: without one the default-mode of the stylesheet;
  XTDE0045 for an unknown mode, one an xsl:mode says is private and one
  without template rules or on-no-match (as in Saxon; the default
  visibility does not count); an initial template starts in the unnamed
  mode, also with an initial mode (as in Saxon) }
{ the result of Sheet (in the namespace m = urn:m) on <doc/> with the
  initial mode Mode }
function InitialModeResult(const Sheet, Mode: string): string;
var
  S: TLandrixXmlXsltStylesheet;
  T: TLandrixXmlXsltTransformer;
  Source: TLandrixXmlXPathTree;
begin
  S := TLandrixXmlXsltStylesheet.Create;
  T := nil;
  Source := TLandrixXmlXPathTree.Create;
  try
    S.LoadFromUtf8(U('<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"' +
      ' xmlns:m="urn:m" ' + Sheet + '<xsl:output omit-xml-declaration="yes"/></xsl:stylesheet>'), U('urn:test'));
    Source.LoadFromUtf8(U('<doc>t</doc>'));
    T := TLandrixXmlXsltTransformer.Create(S);
    T.InitialMode := U(Mode);
    try
      Result := LandrixXmlUtf8ToString(T.TransformToUtf8(Source));
    except
      on E: ELandrixXmlXsltError do
        Result := E.XPathCode;
    end;
  finally
    Source.Free;
    T.Free;
    S.Free;
  end;
end;

{ the result of the pattern stylesheet below with FunctionBody as the
  sequence constructor of f:t that sets $r (a string) }
function RunPatternSheet(const FunctionBody: string): string;
var
  Sheet: TLandrixXmlXsltStylesheet;
  T: TLandrixXmlXsltTransformer;
  Source: TLandrixXmlXPathTree;
begin
  Sheet := TLandrixXmlXsltStylesheet.Create;
  Source := TLandrixXmlXPathTree.Create;
  T := nil;
  try
    Sheet.LoadFromUtf8(U(
      '<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:f="urn:f"' +
      ' xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="f xs">' +
      '<xsl:output omit-xml-declaration="yes"/>' +
      '<xsl:function name="f:t" as="xs:boolean"><xsl:param name="n" as="node()"/>' +
      '<xsl:variable name="r">' + FunctionBody + '</xsl:variable>' +
      '<xsl:sequence select="string($r) != ''never''"/></xsl:function>' +
      '<xsl:template match="r/(a | zz)" mode="m">x</xsl:template>' +
      '<xsl:template match="/"><out><xsl:apply-templates select="r/a"/></out></xsl:template>' +
      '<xsl:template match="r/(a[f:t(.) and xs:integer(@v) = 1] | a[@w])"><hit v="{@v}"/></xsl:template>' +
      '<xsl:template match="a" priority="-9"><miss v="{@v}"/></xsl:template>' +
      '</xsl:stylesheet>'), U('urn:test'));
    Source.LoadFromUtf8(U('<r><a v="x" w="1"/><a v="1"/></r>'));
    T := TLandrixXmlXsltTransformer.Create(Sheet);
    Result := LandrixXmlUtf8ToString(T.TransformToUtf8(Source));
  finally
    T.Free;
    Source.Free;
    Sheet.Free;
  end;
end;

{ A pattern matched while another one is evaluated (the function in a
  predicate applies templates) leaves the outer one's state alone: the
  result is that of the same function without apply-templates (the first
  a fails in the first branch, so it does not match the second one, see
  the unit comment of LandrixXmlXPathEval) }
procedure TestNestedPattern;
var
  Direct: string;
begin
  Direct := RunPatternSheet('k');
  CheckEqualsStr('<out><miss v="x"/><hit v="1"/></out>', Direct, 'the pattern without nesting');
  CheckEqualsStr(Direct, RunPatternSheet('<xsl:apply-templates select="$n" mode="m"/>'),
    'a pattern matched inside a predicate of another');
end;

procedure TestInitialMode;
const
  Bad: array[0..3] of string = ('{urn:m}none', '{urn:m}hidden', '{urn:m}empty', '{urn:m}used');
var
  Sheet: TLandrixXmlXsltStylesheet;
  T: TLandrixXmlXsltTransformer;
  Source: TLandrixXmlXPathTree;
  Raised: string;
  I: Integer;
begin
  Sheet := TLandrixXmlXsltStylesheet.Create;
  T := nil;
  Source := TLandrixXmlXPathTree.Create;
  try
    Sheet.LoadFromUtf8(U(
      '<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:m="urn:m"' +
      ' default-mode="m:d">' +
      '<xsl:mode name="m:pub" visibility="public"/><xsl:mode name="m:priv"/>' +
      '<xsl:mode name="m:hidden" visibility="private"/><xsl:mode name="m:empty" visibility="public"/>' +
      '<xsl:mode name="m:copy" on-no-match="shallow-copy"/>' +
      '<xsl:template match="/" mode="m:hidden">hidden</xsl:template>' +
      '<xsl:template match="x"><xsl:apply-templates mode="m:used"/></xsl:template>' +
      '<xsl:output omit-xml-declaration="yes"/>' +
      '<xsl:template match="/">d</xsl:template>' +
      '<xsl:template match="/" mode="m:pub">pub</xsl:template>' +
      '<xsl:template match="/" mode="m:priv">priv</xsl:template>' +
      '<xsl:template match="/" mode="m:other">other</xsl:template>' +
      '<xsl:template match="/" mode="#unnamed">unnamed</xsl:template>' +
      '<xsl:template name="main"><xsl:apply-templates select="." mode="#current"/></xsl:template>' +
      '</xsl:stylesheet>'), U('urn:test'));
    Source.LoadFromUtf8(U('<doc/>'));
    T := TLandrixXmlXsltTransformer.Create(Sheet);
    CheckEqualsUtf8(U('d'), T.TransformToUtf8(Source), 'the default mode');
    T.InitialMode := U('{urn:m}pub');
    CheckEqualsUtf8(U('pub'), T.TransformToUtf8(Source), 'a public mode');
    T.InitialMode := U('{urn:m}other');
    CheckEqualsUtf8(U('other'), T.TransformToUtf8(Source), 'a mode no xsl:mode declares');
    T.InitialMode := U('{urn:m}priv');
    CheckEqualsUtf8(U('priv'), T.TransformToUtf8(Source), 'a mode of the default visibility');
    T.InitialMode := U('{urn:m}copy');
    CheckEqualsUtf8(U('<doc/>'), T.TransformToUtf8(Source), 'a mode with on-no-match only');
    for I := 0 to High(Bad) do
    begin
      T.InitialMode := U(Bad[I]);
      Raised := '';
      try
        T.TransformToUtf8(Source);
      except
        on E: ELandrixXmlXsltError do
          Raised := E.XPathCode;
      end;
      CheckEqualsStr('XTDE0045', Raised, 'not eligible: ' + Bad[I]);
    end;
    T.InitialMode := '';
    T.InitialTemplate := U('main');
    CheckEqualsUtf8(U('unnamed'), T.TransformToUtf8(Source), 'an initial template');
    T.InitialMode := U('{urn:m}pub');
    CheckEqualsUtf8(U('unnamed'), T.TransformToUtf8(Source), 'an initial template and mode');
    T.InitialMode := U('{urn:m}none');
    Raised := '';
    try
      T.TransformToUtf8(Source);
    except
      on E: ELandrixXmlXsltError do
        Raised := E.XPathCode;
    end;
    CheckEqualsStr('XTDE0045', Raised, 'an initial template and an unknown mode');
    { the default mode without rules, chosen explicitly; a mode only a
      default-mode names, with the mode="#all" rules (as in Saxon) }
    CheckEqualsStr('t', InitialModeResult('default-mode="m:z"><xsl:mode name="m:z"/>', '{urn:m}z'),
      'the empty default mode');
    CheckEqualsStr('ALL', InitialModeResult('><xsl:template name="u" default-mode="m:y"/>' +
      '<xsl:template match="/" mode="#all">ALL</xsl:template>', '{urn:m}y'), 'a mode default-mode names');
  finally
    Source.Free;
    T.Free;
    Sheet.Free;
  end;
end;

procedure Register;
begin
  RegisterTest('Xslt.FileUris', TestFileUris);
  RegisterTest('Xslt.InitialMode', TestInitialMode);
  RegisterTest('Xslt.NestedPattern', TestNestedPattern);
  RegisterTest('Xslt.KeysOutsideCodePage', TestKeysOutsideCodePage);
  RegisterTest('Xslt.Cases', TestCases);
  RegisterTest('Xslt.Api', TestApi);
  RegisterTest('Xslt.NoSource', TestNoSource);
  RegisterTest('Xslt.Messages', TestMessages);
  RegisterTest('Xslt.SystemProperty', TestSystemProperty);
  RegisterTest('Xslt.NextMatchInAnalyzeString', TestNextMatchInAnalyzeString);
  RegisterTest('Xslt.ResultDocuments', TestResultDocuments);
  RegisterTest('Xslt.Rejected', TestRejected);
  RegisterTest('Xslt.RawUnsupported', TestRawUnsupported);
  RegisterTest('Xslt.NumberFormatUnsupported', TestNumberFormatUnsupported);
  RegisterTest('Xslt.ByteOrderMark', TestByteOrderMark);
  RegisterTest('Xslt.NamesOutsideCodePage', TestNamesOutsideCodePage);
  RegisterTest('Xslt.NonNameCharacter', TestNonNameCharacter);
  RegisterTest('Xslt.DocumentWithoutBase', TestDocumentWithoutBase);
  RegisterTest('Xslt.StackBudget', TestStackBudget);
  RegisterTest('Xslt.DeepApiTree', TestDeepApiTree);
  RegisterTest('Xslt.StackDefault', TestStackDefault);
  RegisterTest('Xslt.ManyAttributesCopy', TestManyAttributesCopy);
  RegisterTest('Xslt.RuntimeReviewEdges', TestRuntimeReviewEdges);
  RegisterTest('Xslt.OutputReviewEdges', TestOutputReviewEdges);
  RegisterTest('Xslt.CompilerReviewEdges', TestCompilerReviewEdges);
  RegisterTest('Xslt.StaticErrors', TestStaticErrors);
end;

end.
