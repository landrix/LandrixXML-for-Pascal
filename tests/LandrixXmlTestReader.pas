{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Tests for LandrixXmlReader: token stream, normalization, namespaces,
  API accessors, positions, Skip, handler, limits.

  Token dump format used by CheckTokens (NS = namespace URI in curly
  braces, only if set):
    <nameNS attrNS="value">   start tag ('/>' if empty)
    </nameNS>                 end tag
    T"text"  W"whitespace"  C"cdata"  !"comment"  ?target"data"  Dname
  Values are rendered with LandrixXmlEscapeForMessage (non-ASCII and
  control characters as U+XXXX). }

unit LandrixXmlTestReader;

{$I LandrixXml.inc}

interface

procedure Register;

function DumpTokens(const Xml: AnsiString): string;

implementation

uses
  SysUtils,
  Classes,
  LandrixXmlBase,
  LandrixXmlReader,
  LandrixXmlTestFramework;

const
  NsXmlns = '{http://www.w3.org/2000/xmlns/}';
  NsXml = '{http://www.w3.org/XML/1998/namespace}';

function Esc(const Span: TLandrixXmlSpan): string;
begin
  Result := LandrixXmlEscapeForMessage(LandrixXmlSpanToUtf8(Span), MaxInt);
end;

function NsPart(const Span: TLandrixXmlSpan): string;
begin
  if Span.Len > 0 then
    Result := '{' + Esc(Span) + '}'
  else
    Result := '';
end;

function DumpCurrent(Reader: TLandrixXmlReader): string;
var
  I: Integer;
begin
  case Reader.TokenType of
    xttStartElement:
      begin
        Result := '<' + Esc(Reader.NameSpan) + NsPart(Reader.NamespaceUriSpan);
        for I := 0 to Reader.AttributeCount - 1 do
          Result := Result + ' ' + Esc(Reader.AttributeNameSpan(I)) +
            NsPart(Reader.AttributeNamespaceUriSpan(I)) + '="' +
            Esc(Reader.AttributeValueSpan(I)) + '"';
        if Reader.IsEmptyElement then
          Result := Result + '/>'
        else
          Result := Result + '>';
      end;
    xttEndElement:
      Result := '</' + Esc(Reader.NameSpan) + NsPart(Reader.NamespaceUriSpan) + '>';
    xttText:
      if Reader.IsWhitespace then
        Result := 'W"' + Esc(Reader.ValueSpan) + '"'
      else
        Result := 'T"' + Esc(Reader.ValueSpan) + '"';
    xttCData:
      Result := 'C"' + Esc(Reader.ValueSpan) + '"';
    xttComment:
      Result := '!"' + Esc(Reader.ValueSpan) + '"';
    xttProcessingInstruction:
      Result := '?' + Esc(Reader.NameSpan) + '"' + Esc(Reader.ValueSpan) + '"';
    xttDocumentType:
      Result := 'D' + Esc(Reader.NameSpan);
  else
    Result := '#';
  end;
end;

function DumpTokens(const Xml: AnsiString): string;
var
  Reader: TLandrixXmlReader;
begin
  Result := '';
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromBuffer(PAnsiChar(Xml)^, Length(Xml));
    while Reader.Read do
      Result := Result + DumpCurrent(Reader);
  finally
    Reader.Free;
  end;
end;

procedure CheckTokens(const Xml: AnsiString; const Expected: string; const Name: string);
begin
  CheckEqualsStr(Expected, DumpTokens(Xml), Name);
end;

function A(const S: string): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(S);
end;

procedure CheckErrorCode(Expected, Actual: TLandrixXmlErrorCode; const Msg: string);
begin
  CheckEquals(Ord(Expected), Ord(Actual), Msg + ' (error code)');
end;

{ --- token stream ---------------------------------------------------------- }

procedure TestBasicStructure;
begin
  CheckTokens('<r/>', '<r/></r>', 'empty root');
  CheckTokens('<r></r>', '<r></r>', 'root with end tag');
  CheckTokens('<r>a</r>', '<r>T"a"</r>', 'text');
  CheckTokens('<a x="1" y=''2''><b/>t</a>', '<a x="1" y="2"><b/></b>T"t"</a>', 'attributes and child');
  CheckTokens('<r  a = "1"  ></r >', '<r a="1"></r>', 'white space in tags');
  CheckTokens('<r>a]b]]c</r>', '<r>T"a]b]]c"</r>', 'brackets in text');
  CheckTokens('<r>]]&gt;</r>', '<r>T"]]>"</r>', 'escaped ]]>');
  CheckTokens('<r a="&gt;"/>', '<r a=">"/></r>', '> in attribute');
  CheckTokens('<r a=''"'' b="''"/>', '<r a=""" b="''"/></r>', 'quotes in attributes');
end;

procedure TestReferencesValid;
begin
  CheckTokens('<r>&#65;&#x42;&#xe4;&#x1F600;</r>', '<r>T"ABU+00E4U+1F600"</r>', 'character references');
  CheckTokens('<r>a&amp;b</r>', '<r>T"a&b"</r>', 'coalesced text');
  CheckTokens('<r>&#x10FFFF;&#9;</r>', '<r>T"U+10FFFFU+0009"</r>', 'boundary references');
  CheckTokens('<r a="&#60;&lt;&#x9;"/>', '<r a="<<U+0009"/></r>', 'references in attribute stay literal');
end;

procedure TestLineEnds;
begin
  CheckTokens('<r>a' + #13#10 + 'b' + #13 + 'c' + #10 + 'd</r>',
    '<r>T"aU+000AbU+000AcU+000Ad"</r>', 'text line ends');
  CheckTokens('<r a="x' + #9 + 'y' + #13#10 + 'z&#10;w' + #10 + 'v"/>',
    '<r a="x y zU+000Aw v"/></r>', 'attribute normalization');
  CheckTokens('<r><!--a' + #13#10 + 'b--><?p a' + #13 + 'b?><![CDATA[x' + #13#10 + 'y]]></r>',
    '<r>!"aU+000Ab"?p"aU+000Ab"C"xU+000Ay"</r>', 'line ends in comment, PI, CDATA');
end;

procedure TestWhitespace;
begin
  CheckTokens('<r> <a/>' + #10 + '</r>', '<r>W" "<a/></a>W"U+000A"</r>', 'whitespace-only text');
  CheckTokens('<r>&#32;</r>', '<r>T" "</r>', 'reference is not whitespace');
  CheckTokens(' ' + #10 + '<r/>' + #13#10 + ' ', '<r/></r>', 'prolog/epilog whitespace not reported');
  CheckTokens('<r>' + #13#10 + '</r>', '<r>W"U+000A"</r>', 'CR LF whitespace normalized');
end;

procedure TestCDataCommentPi;
begin
  CheckTokens('<r><![CDATA[<&>]]><![CDATA[]]></r>', '<r>C"<&>"C""</r>', 'CDATA');
  CheckTokens('<r><![CDATA[a]]]></r>', '<r>C"a]"</r>', 'CDATA ending with ]');
  CheckTokens('<?xml version="1.0"?><!--c--><?pi data?><r><!--x--><?p?></r><!--e-->',
    '!"c"?pi"data"<r>!"x"?p""</r>!"e"', 'comments and PIs everywhere');
  CheckTokens('<r><!----></r>', '<r>!""</r>', 'empty comment');
  CheckTokens('<r><!-- - --></r>', '<r>!" - "</r>', 'single dash in comment');
  CheckTokens('<r><?pi   spaced  ?></r>', '<r>?pi"spaced  "</r>', 'PI data starts after white space');
  CheckTokens('<?xml-stylesheet href="a.xsl"?><r/>', '?xml-stylesheet"href="a.xsl""<r/></r>', 'xml-stylesheet');
end;

procedure TestDocType;
var
  Reader: TLandrixXmlReader;
  Xml: AnsiString;
begin
  CheckTokens('<!DOCTYPE r [<!ENTITY e "x>y"> <!-- ] --> <?pi ]?>]><r/>', 'Dr<r/></r>', 'internal subset');
  CheckTokens('<!DOCTYPE r SYSTEM "r.dtd"><r/>', 'Dr<r/></r>', 'external id');
  CheckTokens('<!DOCTYPE r PUBLIC "-//X//Y" ''r.dtd'' [ ]  ><r/>', 'Dr<r/></r>', 'public id and empty subset');
  CheckTokens('<?xml version="1.0"?><!--c--><!DOCTYPE r><!--d--><r/>', '!"c"Dr!"d"<r/></r>', 'misc around doctype');
  Xml := '<!DOCTYPE r SYSTEM "r.dtd"><r/>';
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromBuffer(PAnsiChar(Xml)^, Length(Xml));
    Check(not Reader.HasDocumentType, 'no doctype before reading');
    Check(Reader.Read, 'read doctype');
    Check(Reader.HasDocumentType, 'HasDocumentType');
    CheckEqualsUtf8(A('r'), Reader.NameUtf8, 'doctype name');
    CheckEqualsUtf8(A(' SYSTEM "r.dtd"'), Reader.ValueUtf8, 'raw doctype content');
  finally
    Reader.Free;
  end;
end;

procedure TestNamespaces;
begin
  CheckTokens('<p:r xmlns:p="urn:p" xmlns="urn:d"><c a="1" p:b="2"/></p:r>',
    '<p:r{urn:p} xmlns:p' + NsXmlns + '="urn:p" xmlns' + NsXmlns + '="urn:d">' +
    '<c{urn:d} a="1" p:b{urn:p}="2"/></c{urn:d}></p:r{urn:p}>', 'prefixes and default namespace');
  CheckTokens('<r xmlns="urn:a"><c xmlns=""/></r>',
    '<r{urn:a} xmlns' + NsXmlns + '="urn:a"><c xmlns' + NsXmlns + '=""/></c></r{urn:a}>', 'undeclare default');
  CheckTokens('<r xml:lang="de"/>', '<r xml:lang' + NsXml + '="de"/></r>', 'xml prefix');
  CheckTokens('<r xmlns:xml="http://www.w3.org/XML/1998/namespace"/>',
    '<r xmlns:xml' + NsXmlns + '="http://www.w3.org/XML/1998/namespace"/></r>', 'declaring xml correctly');
  CheckTokens('<a xmlns:p="urn:1"><p:b xmlns:p="urn:2"><p:c/></p:b><p:d/></a>',
    '<a xmlns:p' + NsXmlns + '="urn:1"><p:b{urn:2} xmlns:p' + NsXmlns + '="urn:2"><p:c{urn:2}/></p:c{urn:2}>' +
    '</p:b{urn:2}><p:d{urn:1}/></p:d{urn:1}></a>', 'scoping and redeclaration');
  CheckTokens('<r xmlns:a="urn:x" a:z="1" z="2"/>',
    '<r xmlns:a' + NsXmlns + '="urn:x" a:z{urn:x}="1" z="2"/></r>', 'same local name, different namespaces');
  CheckTokens('<xmlfoo:r xmlns:xmlfoo="urn:x"/>', '<xmlfoo:r{urn:x} xmlns:xmlfoo' + NsXmlns + '="urn:x"/></xmlfoo:r{urn:x}>',
    'prefix starting with xml is allowed');
end;

procedure TestMixedContent;
begin
  CheckTokens('<p>Text <b>fett</b> und <i>kursiv</i>.</p>',
    '<p>T"Text "<b>T"fett"</b>T" und "<i>T"kursiv"</i>T"."</p>', 'mixed content');
  CheckTokens('<p><b>A</b> <i>B</i></p>', '<p><b>T"A"</b>W" "<i>T"B"</i></p>', 'separating space is kept');
end;

procedure TestUnicodeNames;
begin
  CheckTokens('<' + Bytes([$C3, $A4]) + ' ' + Bytes([$E4, $B8, $AD]) + '="1"/>',
    '<U+00E4 U+4E2D="1"/></U+00E4>', 'non-ASCII names');
  CheckTokens('<a' + Bytes([$CC, $81]) + '-.' + Bytes([$C2, $B7]) + '0/>',
    '<aU+0301-.U+00B70/></aU+0301-.U+00B70>', 'name characters that cannot start a name');
  CheckTokens('<_:a xmlns:_="urn:u"/>', '<_:a{urn:u} xmlns:_' + NsXmlns + '="urn:u"/></_:a{urn:u}>', 'underscore prefix');
end;

procedure TestDeclarationValues;
var
  Reader: TLandrixXmlReader;
begin
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromUtf8(A('<?xml version="1.1" standalone="yes"?><r/>'));
    Check(Reader.Read, 'read');
    CheckEqualsUtf8(A('1.1'), Reader.Version, 'version 1.1 accepted');
    CheckEqualsUtf8(A('yes'), Reader.Standalone, 'standalone');
    Reader.LoadFromUtf8(A('<r/>'));
    Check(Reader.Read, 'read without declaration');
    CheckEqualsUtf8('', Reader.Version, 'no version');
    CheckEqualsUtf8('', Reader.Standalone, 'no standalone');
  finally
    Reader.Free;
  end;
end;

{ --- API ----------------------------------------------------------------------- }

procedure TestDepthAndEnd;
var
  Reader: TLandrixXmlReader;
  Depths: string;
begin
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromUtf8(A('<!--c--><a><b>t</b><c/></a>'));
    Depths := '';
    while Reader.Read do
      Depths := Depths + IntToStr(Reader.Depth);
    { comment 0, a 0, b 1, t 2, /b 1, c 1, /c 1, /a 0 }
    CheckEqualsStr('00121110', Depths, 'depths');
    Check(Reader.TokenType = xttEndOfDocument, 'end of document');
    Check(not Reader.Read, 'Read after the end stays False');
    Check(Reader.TokenType = xttEndOfDocument, 'still end of document');
  finally
    Reader.Free;
  end;
end;

procedure TestAccessors;
var
  Reader: TLandrixXmlReader;
  Uri: TLandrixXmlUtf8;
begin
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromUtf8(A('<p:r xmlns:p="urn:p" p:a="x" b="y' + '">t</p:r>'));
    Check(Reader.Read, 'start');
    CheckEqualsUtf8(A('p:r'), Reader.NameUtf8, 'NameUtf8');
    CheckEqualsUtf8(A('p'), Reader.PrefixUtf8, 'PrefixUtf8');
    CheckEqualsUtf8(A('r'), Reader.LocalNameUtf8, 'LocalNameUtf8');
    CheckEqualsUtf8(A('urn:p'), Reader.NamespaceUriUtf8, 'NamespaceUriUtf8');
    CheckEqualsStr('r', Reader.LocalName, 'LocalName');
    CheckEqualsStr('urn:p', Reader.NamespaceUri, 'NamespaceUri');
    CheckEqualsWide(Wide([Ord('r')]), Reader.LocalNameW, 'LocalNameW');
    CheckEquals(3, Reader.AttributeCount, 'AttributeCount');
    Check(Reader.IsNamespaceDeclaration(0), 'xmlns:p is a declaration');
    Check(not Reader.IsNamespaceDeclaration(1), 'p:a is not');
    CheckEquals(1, Reader.AttributeIndex(A('urn:p'), A('a')), 'AttributeIndex prefixed');
    CheckEquals(2, Reader.AttributeIndex('', A('b')), 'AttributeIndex unprefixed');
    CheckEquals(-1, Reader.AttributeIndex('', A('a')), 'AttributeIndex wrong namespace');
    CheckEquals(0, Reader.AttributeIndex(A('http://www.w3.org/2000/xmlns/'), A('p')), 'AttributeIndex xmlns');
    CheckEqualsUtf8(A('x'), Reader.AttributeValueUtf8(1), 'AttributeValueUtf8');
    CheckEqualsStr('y', Reader.AttributeValue(2), 'AttributeValue');
    CheckEqualsUtf8(A('a'), Reader.AttributeLocalNameUtf8(1), 'AttributeLocalNameUtf8');
    CheckEqualsUtf8(A('p:a'), Reader.AttributeNameUtf8(1), 'AttributeNameUtf8');
    CheckEqualsUtf8(A('urn:p'), Reader.AttributeNamespaceUriUtf8(1), 'AttributeNamespaceUriUtf8');
    Check(Reader.LookupNamespace(A('p'), Uri), 'LookupNamespace p');
    CheckEqualsUtf8(A('urn:p'), Uri, 'LookupNamespace p value');
    Check(Reader.LookupNamespace(A('xml'), Uri), 'LookupNamespace xml');
    Check(not Reader.LookupNamespace('', Uri), 'no default namespace');
    Check(not Reader.LookupNamespace(A('q'), Uri), 'unknown prefix');
    try
      Reader.AttributeValueUtf8(3);
      FailNotRaised('ELandrixXmlError for attribute index 3');
    except
      on E: ELandrixXmlError do
        CheckErrorCode(xecInvalidArgument, E.Code, 'attribute index out of range');
    end;
    Check(Reader.Read, 'text');
    CheckEqualsStr('t', Reader.Value, 'Value');
    CheckEquals(0, Reader.AttributeCount, 'no attributes on text');
    Check(Reader.Read, 'end');
    CheckEqualsUtf8(A('urn:p'), Reader.NamespaceUriUtf8, 'end tag keeps namespace');
    Check(Reader.LookupNamespace(A('p'), Uri), 'scope still visible on end tag');
    Check(not Reader.Read, 'end of document');
  finally
    Reader.Free;
  end;
end;

procedure TestUnicodeValues;
var
  Reader: TLandrixXmlReader;
  U: TLandrixXmlUtf8;
begin
  { umlaut, euro, emoji through all three accessors }
  U := Utf8Bytes([$C3, $A4, $E2, $82, $AC, $F0, $9F, $98, $80]);
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromUtf8(A('<r a="') + U + A('">') + U + A('</r>'));
    Check(Reader.Read, 'start');
    CheckEqualsUtf8(U, Reader.AttributeValueUtf8(0), 'attribute UTF-8');
    CheckEqualsWide(Wide([$E4, $20AC, $D83D, $DE00]), Reader.AttributeValueW(0), 'attribute wide');
    Check(Reader.Read, 'text');
    CheckEqualsUtf8(U, Reader.ValueUtf8, 'text UTF-8');
    CheckEqualsWide(Wide([$E4, $20AC, $D83D, $DE00]), Reader.ValueW, 'text wide');
  finally
    Reader.Free;
  end;
end;

procedure TestSkip;
var
  Reader: TLandrixXmlReader;
begin
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromUtf8(A('<r><a><b/>x<c><d/></c></a><e/></r>'));
    Check(Reader.Read and Reader.Read, 'positioned on a');
    CheckEqualsUtf8(A('a'), Reader.NameUtf8, 'on a');
    Reader.Skip;
    Check(Reader.TokenType = xttEndElement, 'Skip stops on the end tag');
    CheckEqualsUtf8(A('a'), Reader.NameUtf8, 'end tag of a');
    Check(Reader.Read, 'next');
    CheckEqualsUtf8(A('e'), Reader.NameUtf8, 'sibling after skip');
    Reader.Skip;
    Check(Reader.TokenType = xttEndElement, 'Skip on empty element');
    CheckEqualsUtf8(A('e'), Reader.NameUtf8, 'end of e');
    Reader.LoadFromUtf8(A('<r><a><b></a></r>'));
    Check(Reader.Read and Reader.Read, 'positioned on a (malformed subtree)');
    try
      Reader.Skip;
      FailNotRaised('Skip must check the subtree');
    except
      on E: ELandrixXmlError do
        CheckErrorCode(xecSyntax, E.Code, 'Skip error');
    end;
  finally
    Reader.Free;
  end;
end;

procedure TestReadElementText;
var
  Reader: TLandrixXmlReader;
begin
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromUtf8(A('<r><a>12<!-- x -->3<?pi d?>&amp;<![CDATA[<4>]]> 5 </a>' +
      '<b/><c></c><d>') + Utf8Bytes([$C3, $A4]) + A('</d><e>x</e></r>'));
    Check(Reader.Read and Reader.Read, 'positioned on a');
    CheckEqualsUtf8(A('123&<4> 5 '), Reader.ReadElementTextUtf8, 'joined text');
    Check(Reader.TokenType = xttEndElement, 'stops on the end tag');
    CheckEqualsUtf8(A('a'), Reader.NameUtf8, 'end tag of a');
    Check(Reader.Read, 'b');
    CheckEqualsUtf8(A(''), Reader.ReadElementTextUtf8, 'empty element');
    CheckEqualsUtf8(A('b'), Reader.NameUtf8, 'end of b');
    Check(Reader.TokenType = xttEndElement, 'end token of <b/>');
    Check(Reader.Read, 'c');
    CheckEqualsUtf8(A(''), Reader.ReadElementTextUtf8, 'no content');
    Check(Reader.Read, 'd');
    CheckEqualsWide(Wide([$E4]), Reader.ReadElementTextW, 'wide variant');
    Check(Reader.Read, 'e');
    CheckEqualsStr('x', Reader.ReadElementText, 'native variant');
    Check(Reader.Read and (Reader.TokenType = xttEndElement), 'end of r');
    try
      Reader.ReadElementTextUtf8;
      FailNotRaised('not on a start element');
    except
      on E: ELandrixXmlError do
        CheckErrorCode(xecInvalidOperation, E.Code, 'wrong token');
    end;
    Check(Reader.Read = False, 'reader still usable after misuse');

    { a child element: error at the child, the reader stays usable }
    Reader.LoadFromUtf8(A('<r><a>x<b>y</b>z</a><c>w</c></r>'));
    Check(Reader.Read and Reader.Read, 'positioned on a');
    try
      Reader.ReadElementTextUtf8;
      FailNotRaised('child element');
    except
      on E: ELandrixXmlError do
      begin
        CheckErrorCode(xecUnexpectedElement, E.Code, 'child element code');
        CheckEquals(1, E.Line, 'child line');
        CheckEquals(8, E.Column, 'child column');
        CheckEqualsInt64(7, E.Offset, 'child offset');
      end;
    end;
    Check(Reader.TokenType = xttStartElement, 'stands on the child');
    CheckEqualsUtf8(A('b'), Reader.NameUtf8, 'child name');
    CheckEqualsUtf8(A('/r/a/b'), Reader.ElementPathUtf8, 'path of the child');
    CheckEquals(2, Reader.Depth, 'depth of the child');
    Reader.Skip;
    Check(Reader.Read and (Reader.TokenType = xttText), 'text after the child');
    Check(Reader.Read and (Reader.TokenType = xttEndElement), 'end of a');
    Check(Reader.Read, 'c');
    CheckEqualsUtf8(A('w'), Reader.ReadElementTextUtf8, 'continues after the error');
    CheckEquals(1, Reader.Depth, 'depth of the end tag');

    { an empty child element; the message names both elements }
    Reader.LoadFromUtf8(A('<r><p:a xmlns:p="urn:p">x<p:b/></p:a></r>'));
    Check(Reader.Read and Reader.Read, 'positioned on p:a');
    try
      Reader.ReadElementTextUtf8;
      FailNotRaised('empty child element');
    except
      on E: ELandrixXmlError do
      begin
        CheckErrorCode(xecUnexpectedElement, E.Code, 'empty child code');
        Check(Pos('"p:b"', E.Message) > 0, 'message names the child: ' + E.Message);
        Check(Pos('"p:a"', E.Message) > 0, 'message names the parent: ' + E.Message);
      end;
    end;
    Check(Reader.IsEmptyElement, 'stands on <p:b/>');
    Reader.Skip;
    CheckEqualsUtf8(A('p:b'), Reader.NameUtf8, 'end of the empty child');
    Check(Reader.Read and (Reader.TokenType = xttEndElement), 'end of p:a');
    CheckEqualsUtf8(A('p:a'), Reader.NameUtf8, 'end of p:a name');

    { malformed content still kills the reader }
    Reader.LoadFromUtf8(A('<r><a>x</b></r>'));
    Check(Reader.Read and Reader.Read, 'positioned on a (malformed)');
    try
      Reader.ReadElementTextUtf8;
      FailNotRaised('malformed content');
    except
      on E: ELandrixXmlError do
        CheckErrorCode(xecSyntax, E.Code, 'malformed code');
    end;
    CheckEqualsUtf8(A('/r/a'), Reader.ElementPathUtf8, 'path after the error');
    try
      Reader.Read;
      FailNotRaised('dead after a syntax error');
    except
      on E: ELandrixXmlError do
        CheckErrorCode(xecInvalidOperation, E.Code, 'dead reader');
    end;
  finally
    Reader.Free;
  end;
end;

procedure TestElementPath;
var
  Reader: TLandrixXmlReader;
begin
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromUtf8(A('<?xml version="1.0"?><!-- c --><Invoice xmlns:cbc="urn:c">' +
      '<cbc:ID>1</cbc:ID><L><x/></L></Invoice><?pi?>'));
    CheckEqualsUtf8(A(''), Reader.ElementPathUtf8, 'before the first token');
    Check(Reader.Read and (Reader.TokenType = xttComment), 'prolog comment');
    CheckEqualsUtf8(A(''), Reader.ElementPathUtf8, 'prolog');
    Check(Reader.Read, 'root');
    CheckEqualsUtf8(A('/Invoice'), Reader.ElementPathUtf8, 'root start');
    Check(Reader.Read, 'ID');
    CheckEqualsUtf8(A('/Invoice/cbc:ID'), Reader.ElementPathUtf8, 'ID start');
    Check(Reader.Read and (Reader.TokenType = xttText), 'text');
    CheckEqualsUtf8(A('/Invoice/cbc:ID'), Reader.ElementPathUtf8, 'text in ID');
    Check(Reader.Read and (Reader.TokenType = xttEndElement), 'ID end');
    CheckEqualsUtf8(A('/Invoice/cbc:ID'), Reader.ElementPathUtf8, 'ID end tag');
    Check(Reader.Read and Reader.Read, 'x');
    CheckEqualsStr('/Invoice/L/x', Reader.ElementPath, 'x start (native)');
    Check(Reader.Read and (Reader.TokenType = xttEndElement), 'x end');
    CheckEqualsWide(Wide([Ord('/'), Ord('I'), Ord('n'), Ord('v'), Ord('o'), Ord('i'),
      Ord('c'), Ord('e'), Ord('/'), Ord('L'), Ord('/'), Ord('x')]),
      Reader.ElementPathW, 'end tag of <x/> (wide)');
    Check(Reader.Read and Reader.Read, 'root end');
    CheckEqualsUtf8(A('/Invoice'), Reader.ElementPathUtf8, 'root end tag');
    Check(Reader.Read and (Reader.TokenType = xttProcessingInstruction), 'epilog');
    CheckEqualsUtf8(A(''), Reader.ElementPathUtf8, 'epilog');
    Check(not Reader.Read, 'end');
    CheckEqualsUtf8(A(''), Reader.ElementPathUtf8, 'end of document');
  finally
    Reader.Free;
  end;
end;

type
  TCountingHandler = class(TLandrixXmlHandler)
  public
    Log: string;
    procedure StartElement(Reader: TLandrixXmlReader); override;
    procedure EndElement(Reader: TLandrixXmlReader); override;
    procedure Text(Reader: TLandrixXmlReader); override;
    procedure EndDocument(Reader: TLandrixXmlReader); override;
  end;

procedure TCountingHandler.StartElement(Reader: TLandrixXmlReader);
begin
  Log := Log + 'S' + Reader.LocalName;
end;

procedure TCountingHandler.EndElement(Reader: TLandrixXmlReader);
begin
  Log := Log + 'E' + Reader.LocalName;
end;

procedure TCountingHandler.Text(Reader: TLandrixXmlReader);
begin
  Log := Log + 'T' + Reader.Value;
end;

{$IFDEF FPC}
  {$PUSH}
  {$WARN 5024 OFF}
{$ENDIF}
procedure TCountingHandler.EndDocument(Reader: TLandrixXmlReader);
begin
  Log := Log + '.';
end;
{$IFDEF FPC}
  {$POP}
{$ENDIF}

procedure TestHandler;
var
  Reader: TLandrixXmlReader;
  Handler: TCountingHandler;
begin
  Reader := TLandrixXmlReader.Create;
  Handler := TCountingHandler.Create;
  try
    Reader.LoadFromUtf8(A('<r><!--c--><a>x</a><b/></r>'));
    Reader.Run(Handler);
    CheckEqualsStr('SrSaTxEaSbEbEr.', Handler.Log, 'handler events');
  finally
    Handler.Free;
    Reader.Free;
  end;
end;

procedure TestPositions;
var
  Reader: TLandrixXmlReader;
  Xml: AnsiString;
begin
  Reader := TLandrixXmlReader.Create;
  try
    Xml := '<r>' + #13#10 + '  <a x="1"/>' + #10 + 'ab<b/></r>';
    Reader.LoadFromBuffer(PAnsiChar(Xml)^, Length(Xml));
    Check(Reader.Read, 'r');
    CheckEquals(1, Reader.Line, 'r line');
    CheckEquals(1, Reader.Column, 'r column');
    CheckEqualsInt64(0, Reader.Offset, 'r offset');
    Check(Reader.Read, 'whitespace');
    CheckEquals(1, Reader.Line, 'whitespace line');
    CheckEquals(4, Reader.Column, 'whitespace column');
    Check(Reader.Read, 'a');
    CheckEquals(2, Reader.Line, 'a line (CR LF)');
    CheckEquals(3, Reader.Column, 'a column');
    CheckEqualsInt64(7, Reader.Offset, 'a offset');
    Check(Reader.Read and Reader.Read, 'end a, text');
    CheckEquals(2, Reader.Line, 'text starts with the LF at the end of line 2');
    CheckEquals(13, Reader.Column, 'text column');
    Check(Reader.Read, 'b');
    CheckEquals(3, Reader.Line, 'b line');
    CheckEquals(3, Reader.Column, 'b column');
    { descending query after ascending ones }
    Reader.LoadFromBuffer(PAnsiChar(Xml)^, Length(Xml));
    Check(Reader.Read and Reader.Read and Reader.Read, 'positioned on a again');
    CheckEquals(3, Reader.Column, 'a column');
    CheckEquals(2, Reader.Line, 'a line');
  finally
    Reader.Free;
  end;
end;

{ The positions after a token are the ones Xerces reports (column of the
  character after the tag, 1-based). }
procedure TestTokenEndPositions;
var
  Reader: TLandrixXmlReader;
  Xml: AnsiString;
begin
  Reader := TLandrixXmlReader.Create;
  try
    Xml := '<r a="1">' + #13#10 + 'xy<b/>' + #10 + '<c' + #10 + '  d="2">t</c></r>';
    Reader.LoadFromBuffer(PAnsiChar(Xml)^, Length(Xml));
    Check(Reader.Read, 'r');
    CheckEquals(1, Reader.TokenEndLine, 'after r line');
    CheckEquals(10, Reader.TokenEndColumn, 'after r column');
    CheckEquals(1, Reader.Line, 'start of r after the end query');
    Check(Reader.Read, 'text');
    CheckEquals(2, Reader.TokenEndLine, 'after text line');
    CheckEquals(3, Reader.TokenEndColumn, 'after text column');
    Check(Reader.Read, 'b');
    CheckEquals(7, Reader.TokenEndColumn, 'after <b/>');
    Check(Reader.Read, 'end of b');
    CheckEquals(7, Reader.TokenEndColumn, 'end token of <b/> ends there too');
    Check(Reader.Read and Reader.Read, 'LF, c');
    CheckEquals(3, Reader.Line, 'c line');
    CheckEquals(4, Reader.TokenEndLine, 'after the multi-line start tag');
    CheckEquals(9, Reader.TokenEndColumn, 'after the multi-line start tag column');
    Check(Reader.Read and Reader.Read, 'text, end c');
    CheckEquals(14, Reader.TokenEndColumn, 'after </c>');
    Check(Reader.Read, 'end r');
    CheckEquals(18, Reader.TokenEndColumn, 'after </r>');
  finally
    Reader.Free;
  end;
end;

procedure TestPositionsConverted;
var
  Reader: TLandrixXmlReader;
  Xml: AnsiString;
begin
  { Windows-1252: offsets refer to the original single-byte input }
  Xml := '<?xml version="1.0" encoding="windows-1252"?><r>' + Bytes([$E4, $80]) + '<a/></r>';
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromBuffer(PAnsiChar(Xml)^, Length(Xml));
    Check(Reader.Read and Reader.Read and Reader.Read, 'positioned on a');
    CheckEqualsUtf8(A('a'), Reader.NameUtf8, 'on a');
    CheckEqualsInt64(50, Reader.Offset, 'original offset of a');
    CheckEquals(51, Reader.Column, 'column counts characters');
  finally
    Reader.Free;
  end;
end;

procedure TestPositionsUtf16;
var
  Reader: TLandrixXmlReader;
  Xml: AnsiString;
  Offsets: string;
begin
  { UTF-16LE with BOM: <r> a-umlaut emoji <a/> </r> }
  Xml := Bytes([$FF, $FE, $3C, 0, $72, 0, $3E, 0, $E4, 0, $3D, $D8, $00, $DE,
    $3C, 0, $61, 0, $2F, 0, $3E, 0, $3C, 0, $2F, 0, $72, 0, $3E, 0]);
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromBuffer(PAnsiChar(Xml)^, Length(Xml));
    Offsets := '';
    while Reader.Read do
      Offsets := Offsets + IntToStr(Reader.Offset) + ' ';
    CheckEqualsStr('2 8 14 14 22 ', Offsets, 'token offsets in the original UTF-16 bytes');
  finally
    Reader.Free;
  end;
end;

procedure TestScratchRelocation;
var
  Reader: TLandrixXmlReader;
  Long, Expected: TLandrixXmlUtf8;
  I: Integer;
begin
  { decoded attribute values longer than the initial scratch capacity }
  Long := '';
  Expected := '';
  for I := 1 to 300 do
  begin
    Long := Long + A('x&amp;');
    Expected := Expected + A('x&');
  end;
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromUtf8(A('<r a="') + Long + A('" b="') + Long + A('" c="&lt;"/>'));
    Check(Reader.Read, 'start');
    CheckEqualsUtf8(Expected, Reader.AttributeValueUtf8(0), 'first long value');
    CheckEqualsUtf8(Expected, Reader.AttributeValueUtf8(1), 'second long value');
    CheckEqualsUtf8(A('<'), Reader.AttributeValueUtf8(2), 'short value after relocation');
  finally
    Reader.Free;
  end;
end;

procedure TestMoreEdgeCases;
var
  Reader: TLandrixXmlReader;
  Uri: TLandrixXmlUtf8;
begin
  CheckTokens('<r xmlns:a="u&amp;v"><a:b/></r>',
    '<r xmlns:a' + NsXmlns + '="u&v"><a:b{u&v}/></a:b{u&v}></r>', 'namespace URI with a reference');
  CheckTokens('<r><!--->x--></r>', '<r>!"->x"</r>', 'comment starting with ->');
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromUtf8(A('<r><e/></r>'));
    Check(Reader.Read and Reader.Read, 'on e');
    Check(Reader.IsEmptyElement, 'start token of <e/>');
    Check(Reader.Read, 'end of e');
    Check(Reader.TokenType = xttEndElement, 'end token');
    Check(Reader.IsEmptyElement, 'end token of <e/>');
    Check(Reader.Read, 'end of r');
    Check(not Reader.IsEmptyElement, 'end token of <r></r>');
    Check(Reader.LookupNamespace(A('xmlns'), Uri), 'xmlns prefix is bound by definition');
    CheckEqualsUtf8(A('http://www.w3.org/2000/xmlns/'), Uri, 'xmlns namespace');
  finally
    Reader.Free;
  end;
end;

procedure TestMaxDepth;
var
  Reader: TLandrixXmlReader;
begin
  Reader := TLandrixXmlReader.Create;
  try
    try
      Reader.MaxDepth := 0;
      FailNotRaised('ELandrixXmlError for MaxDepth 0');
    except
      on E: ELandrixXmlError do
        CheckErrorCode(xecInvalidArgument, E.Code, 'MaxDepth 0');
    end;
    CheckEquals(LandrixXmlDefaultMaxDepth, Reader.MaxDepth, 'default kept');
    Reader.MaxDepth := 3;
    Reader.LoadFromUtf8(A('<a><b><c/></b></a>'));
    while Reader.Read do
      ;
    Reader.LoadFromUtf8(A('<a><b><c><d/></c></b></a>'));
    try
      while Reader.Read do
        ;
      FailNotRaised('ELandrixXmlError for depth 4');
    except
      on E: ELandrixXmlError do
      begin
        CheckErrorCode(xecLimit, E.Code, 'depth 4');
        CheckEquals(10, E.Column, 'depth error at <d');
      end;
    end;
  finally
    Reader.Free;
  end;
end;

procedure TestDefaultDepthIsIterative;
var
  Reader: TLandrixXmlReader;
  Xml: TLandrixXmlUtf8;
  I, Count: Integer;
begin
  { 10000 levels: no recursion, only the limit matters }
  Xml := '';
  for I := 1 to 10000 do
    Xml := Xml + A('<a>');
  for I := 1 to 10000 do
    Xml := Xml + A('</a>');
  Reader := TLandrixXmlReader.Create;
  try
    Reader.MaxDepth := 10000;
    Reader.LoadFromUtf8(Xml);
    Count := 0;
    while Reader.Read do
      Inc(Count);
    CheckEquals(20000, Count, 'tokens of a deep document');
  finally
    Reader.Free;
  end;
end;

procedure TestErrorStateAndReuse;
var
  Reader: TLandrixXmlReader;
begin
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromUtf8(A('<r><a></r>'));
    try
      while Reader.Read do
        ;
      FailNotRaised('ELandrixXmlError for mismatched tags');
    except
      on E: ELandrixXmlError do ;
    end;
    try
      Reader.Read;
      FailNotRaised('ELandrixXmlError for Read after error');
    except
      on E: ELandrixXmlError do
        CheckErrorCode(xecInvalidOperation, E.Code, 'Read after error');
    end;
    Reader.LoadFromUtf8(A('<x/>'));
    Check(Reader.Read, 'reader reusable after load');
    CheckEqualsUtf8(A('x'), Reader.NameUtf8, 'new document');
  finally
    Reader.Free;
  end;
end;

procedure TestManyAttributes;
var
  Xml: TLandrixXmlUtf8;
  I: Integer;
  Reader: TLandrixXmlReader;
begin
  { above the hash threshold }
  Xml := A('<r xmlns:p="urn:p"');
  for I := 1 to 200 do
    Xml := Xml + A(' a' + IntToStr(I) + '="' + IntToStr(I) + '" p:b' + IntToStr(I) + '="x"');
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromUtf8(Xml + A('/>'));
    Check(Reader.Read, 'start');
    CheckEquals(401, Reader.AttributeCount, 'attribute count');
    CheckEquals(400, Reader.AttributeIndex(A('urn:p'), A('b200')), 'last prefixed attribute');
    Reader.LoadFromUtf8(Xml + A(' a77="dup"/>'));
    try
      Reader.Read;
      FailNotRaised('duplicate among many');
    except
      on E: ELandrixXmlError do
        CheckErrorCode(xecSyntax, E.Code, 'duplicate among many');
    end;
    Reader.LoadFromUtf8(Xml + A(' xmlns:q="urn:p" q:b5="dup"/>'));
    try
      Reader.Read;
      FailNotRaised('expanded duplicate among many');
    except
      on E: ELandrixXmlError do
        CheckErrorCode(xecNamespace, E.Code, 'expanded duplicate among many');
    end;
  finally
    Reader.Free;
  end;
end;

procedure TestLargeDocument;
var
  Buf: TLandrixXmlBuffer;
  Reader: TLandrixXmlReader;
  I, Elements, TextBytes: Integer;
begin
  Buf := TLandrixXmlBuffer.Create;
  Reader := TLandrixXmlReader.Create;
  try
    Buf.AppendAscii('<root xmlns="urn:gaeb">');
    for I := 1 to 50000 do
      Buf.AppendUtf8(A('<item id="' + IntToStr(I) + '"><t>Text &amp; more ' +
        IntToStr(I) + '</t><b>bold</b> tail</item>' + #10));
    Buf.AppendAscii('</root>');
    Reader.LoadFromBuffer(Buf.Data^, Buf.Size);
    Elements := 0;
    TextBytes := 0;
    while Reader.Read do
      case Reader.TokenType of
        xttStartElement: Inc(Elements);
        xttText: Inc(TextBytes, Reader.ValueSpan.Len);
      else
        { other tokens are not counted }
      end;
    CheckEquals(1 + 3 * 50000, Elements, 'elements');
    Check(TextBytes > 50000 * 20, 'text read');
  finally
    Reader.Free;
    Buf.Free;
  end;
end;

procedure Register;
begin
  RegisterTest('Reader.BasicStructure', TestBasicStructure);
  RegisterTest('Reader.ReferencesValid', TestReferencesValid);
  RegisterTest('Reader.LineEnds', TestLineEnds);
  RegisterTest('Reader.Whitespace', TestWhitespace);
  RegisterTest('Reader.CDataCommentPi', TestCDataCommentPi);
  RegisterTest('Reader.DocType', TestDocType);
  RegisterTest('Reader.Namespaces', TestNamespaces);
  RegisterTest('Reader.MixedContent', TestMixedContent);
  RegisterTest('Reader.UnicodeNames', TestUnicodeNames);
  RegisterTest('Reader.DeclarationValues', TestDeclarationValues);
  RegisterTest('Reader.DepthAndEnd', TestDepthAndEnd);
  RegisterTest('Reader.Accessors', TestAccessors);
  RegisterTest('Reader.UnicodeValues', TestUnicodeValues);
  RegisterTest('Reader.Skip', TestSkip);
  RegisterTest('Reader.ReadElementText', TestReadElementText);
  RegisterTest('Reader.ElementPath', TestElementPath);
  RegisterTest('Reader.Handler', TestHandler);
  RegisterTest('Reader.Positions', TestPositions);
  RegisterTest('Reader.TokenEndPositions', TestTokenEndPositions);
  RegisterTest('Reader.PositionsConverted', TestPositionsConverted);
  RegisterTest('Reader.PositionsUtf16', TestPositionsUtf16);
  RegisterTest('Reader.ScratchRelocation', TestScratchRelocation);
  RegisterTest('Reader.MoreEdgeCases', TestMoreEdgeCases);
  RegisterTest('Reader.MaxDepth', TestMaxDepth);
  RegisterTest('Reader.DeepDocument', TestDefaultDepthIsIterative);
  RegisterTest('Reader.ErrorStateAndReuse', TestErrorStateAndReuse);
  RegisterTest('Reader.ManyAttributes', TestManyAttributes);
  RegisterTest('Reader.LargeDocument', TestLargeDocument);
end;

end.
