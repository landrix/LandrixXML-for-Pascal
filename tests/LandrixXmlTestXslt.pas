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
  LandrixXmlXslt,
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
    T.SetParameterXPath(U('x'), U('(1, 2) ! string()'));
    Raised := '';
    try
      T.TransformToUtf8(Source);
    except
      on E: ELandrixXmlXPathError do
        Raised := E.XPathCode;
    end;
    CheckEqualsStr('XPST0003', Raised, 'an XPath parameter in the XPath 2.0 profile');
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
      T.SetOutputProperty(U('doctype-system'), U('x.dtd'));
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
      LandrixXmlVersion + '|no'), T.TransformToUtf8(nil), 'system-property()');
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

{ What the subset does not support is rejected when the stylesheet is
  loaded (xecUnsupported); errors name module and line. }
procedure TestRejected;
const
  Head = '<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">';
  Cases: array[0..14] of string = (
    '<xsl:accumulator name="a" initial-value="0"/><xsl:template match="/"/>',
    '<xsl:mode name="m"/><xsl:template match="/"/>',
    '<xsl:template match="/"><x xsl:expand-text="yes">{1}</x></xsl:template>',
    '<xsl:output cdata-section-elements="a"/><xsl:template match="/"/>',
    '<xsl:output doctype-system="x.dtd"/><xsl:template match="/"/>',
    '<xsl:output encoding="UTF-16"/><xsl:template match="/"/>',
    '<xsl:template match="/"><xsl:for-each select="1"><xsl:sort lang="de"/></xsl:for-each></xsl:template>',
    '<xsl:template match="/"><xsl:number lang="de"/></xsl:template>',
    '<xsl:key name="p:k" xmlns:p="urn:p" match="a" use="."/><xsl:template match="/"/>',
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

procedure Register;
begin
  RegisterTest('Xslt.Cases', TestCases);
  RegisterTest('Xslt.Api', TestApi);
  RegisterTest('Xslt.NoSource', TestNoSource);
  RegisterTest('Xslt.Messages', TestMessages);
  RegisterTest('Xslt.SystemProperty', TestSystemProperty);
  RegisterTest('Xslt.NextMatchInAnalyzeString', TestNextMatchInAnalyzeString);
  RegisterTest('Xslt.ResultDocuments', TestResultDocuments);
  RegisterTest('Xslt.Rejected', TestRejected);
end;

end.
