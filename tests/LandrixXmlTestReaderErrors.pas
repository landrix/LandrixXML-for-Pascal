{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Negative tests for LandrixXmlReader: malformed XML must be rejected with
  the right error code and position (line, column of the offending
  character). }

unit LandrixXmlTestReaderErrors;

{$I LandrixXml.inc}

interface

procedure Register;

implementation

uses
  SysUtils,
  LandrixXmlBase,
  LandrixXmlReader,
  LandrixXmlTestFramework;

procedure Bad(const Xml: AnsiString; Code: TLandrixXmlErrorCode;
  Line, Column: Integer; const Name: string);
var
  Reader: TLandrixXmlReader;
begin
  Reader := TLandrixXmlReader.Create;
  try
    try
      Reader.LoadFromBuffer(PAnsiChar(Xml)^, Length(Xml));
      while Reader.Read do
        ;
      FailNotRaised('ELandrixXmlError for ' + Name);
    except
      on E: ELandrixXmlError do
      begin
        CheckEquals(Ord(Code), Ord(E.Code), Name + ' (error code; message: ' + E.Message + ')');
        CheckEquals(Line, E.Line, Name + ' (line; message: ' + E.Message + ')');
        CheckEquals(Column, E.Column, Name + ' (column; message: ' + E.Message + ')');
      end;
    end;
  finally
    Reader.Free;
  end;
end;

procedure TestDocumentStructure;
begin
  Bad('', xecSyntax, 1, 1, 'empty document');
  Bad('   ', xecSyntax, 1, 4, 'only white space');
  Bad('<?xml version="1.0"?>', xecSyntax, 1, 22, 'only a declaration');
  Bad('<!--c-->', xecSyntax, 1, 9, 'only a comment');
  Bad('abc', xecSyntax, 1, 1, 'text before root');
  Bad('<r>', xecSyntax, 1, 4, 'unclosed root');
  Bad('<r>abc', xecSyntax, 1, 7, 'text then end of input');
  Bad('<r><a></r>', xecSyntax, 1, 9, 'mismatched end tag');
  Bad('<r></s>', xecSyntax, 1, 6, 'wrong end tag');
  Bad('<r/><r/>', xecSyntax, 1, 5, 'two roots');
  Bad('<r/>x', xecSyntax, 1, 5, 'text after root');
  Bad('<r/>&amp;', xecSyntax, 1, 5, 'reference after root');
  Bad('</r>', xecSyntax, 1, 1, 'end tag without start tag');
  Bad('<r></r', xecSyntax, 1, 7, 'end tag without >');
  Bad('<r></r x>', xecSyntax, 1, 8, 'garbage in end tag');
  Bad('<r', xecSyntax, 1, 3, 'unterminated start tag');
  Bad('<1r/>', xecSyntax, 1, 2, 'name starting with a digit');
  Bad('< r/>', xecSyntax, 1, 2, 'space before name');
  Bad('<r>' + #10 + '  <a>' + #10 + '</r>', xecSyntax, 3, 3, 'line/column of a mismatch');
  Bad('<r>' + #13#10 + #13#10 + '&x;</r>', xecSyntax, 3, 1, 'CR LF counted once');
  Bad('<r>' + Bytes([$C3, $A4, $C3, $A4]) + '&x;</r>', xecSyntax, 1, 6, 'columns count characters');
end;

procedure TestAttributes;
begin
  Bad('<r a="1" a="2"/>', xecSyntax, 1, 10, 'duplicate attribute');
  Bad('<r a="1"b="2"/>', xecSyntax, 1, 9, 'missing white space between attributes');
  Bad('<r a=1/>', xecSyntax, 1, 6, 'unquoted value');
  Bad('<r a/>', xecSyntax, 1, 5, 'attribute without value');
  Bad('<r a="<"/>', xecSyntax, 1, 7, '< in attribute value');
  Bad('<r a="x/>', xecSyntax, 1, 6, 'unterminated attribute value');
  Bad('<r a="x''/>', xecSyntax, 1, 6, 'mismatched quotes');
  Bad('<r a="&b;"/>', xecSyntax, 1, 7, 'undeclared entity in attribute');
  Bad('<r a="' + #1 + '"/>', xecInvalidChar, 1, 7, 'control character in attribute');
end;

procedure TestReferences;
begin
  Bad('<r>&foo;</r>', xecSyntax, 1, 4, 'undeclared entity');
  Bad('<r>&amp</r>', xecSyntax, 1, 4, 'entity without ;');
  Bad('<r>&;</r>', xecSyntax, 1, 5, 'empty entity name');
  Bad('<r>& x;</r>', xecSyntax, 1, 5, 'space after &');
  Bad('<r>&#;</r>', xecSyntax, 1, 4, 'empty decimal reference');
  Bad('<r>&#x;</r>', xecSyntax, 1, 4, 'empty hex reference');
  Bad('<r>&#X41;</r>', xecSyntax, 1, 4, 'uppercase X');
  Bad('<r>&#12a;</r>', xecSyntax, 1, 4, 'garbage in decimal reference');
  Bad('<r>&#65</r>', xecSyntax, 1, 4, 'reference without ;');
  Bad('<r>&#0;</r>', xecInvalidChar, 1, 4, 'reference to NUL');
  Bad('<r>&#x1;</r>', xecInvalidChar, 1, 4, 'reference to U+0001');
  Bad('<r>&#xC;</r>', xecInvalidChar, 1, 4, 'reference to form feed');
  Bad('<r>&#xD800;</r>', xecInvalidChar, 1, 4, 'reference to a surrogate');
  Bad('<r>&#xFFFE;</r>', xecInvalidChar, 1, 4, 'reference to U+FFFE');
  Bad('<r>&#xFFFF;</r>', xecInvalidChar, 1, 4, 'reference to U+FFFF');
  Bad('<r>&#x110000;</r>', xecInvalidChar, 1, 4, 'reference above U+10FFFF');
  Bad('<r>&#99999999999999999999;</r>', xecInvalidChar, 1, 4, 'overflowing reference');
  Bad('<!DOCTYPE r [<!ENTITY e "x">]><r>&e;</r>', xecSyntax, 1, 34, 'DTD entity is not expanded');
end;

procedure TestCharacters;
begin
  Bad('<r>' + #1 + '</r>', xecInvalidChar, 1, 4, 'U+0001 in text');
  Bad('<r>a' + #8 + '</r>', xecInvalidChar, 1, 5, 'backspace in text');
  Bad('<r>' + Bytes([$EF, $BF, $BF]) + '</r>', xecInvalidChar, 1, 4, 'U+FFFF in text');
  Bad('<r>' + Bytes([$EF, $BF, $BE]) + '</r>', xecInvalidChar, 1, 4, 'U+FFFE in text');
  Bad('<r><!--' + #2 + '--></r>', xecInvalidChar, 1, 8, 'control in comment');
  Bad('<r><![CDATA[' + #3 + ']]></r>', xecInvalidChar, 1, 13, 'control in CDATA');
  Bad('<r><?p ' + #4 + '?></r>', xecInvalidChar, 1, 8, 'control in PI');
  Bad('<r>]]></r>', xecSyntax, 1, 4, ']]> in text');
  Bad('<r>a]]>b</r>', xecSyntax, 1, 5, ']]> inside text');
end;

procedure TestCommentsCDataPis;
begin
  Bad('<r><!-- a -- b --></r>', xecSyntax, 1, 11, '-- in comment');
  Bad('<r><!-- a ---></r>', xecSyntax, 1, 11, 'comment ending with --->');
  Bad('<r><!-- a </r>', xecSyntax, 1, 4, 'unterminated comment');
  Bad('<r><!- a --></r>', xecSyntax, 1, 4, 'malformed comment start');
  Bad('<r><![CDATA[x</r>', xecSyntax, 1, 4, 'unterminated CDATA');
  Bad('<r><![cdata[x]]></r>', xecSyntax, 1, 4, 'lowercase CDATA');
  Bad('<![CDATA[x]]><r/>', xecSyntax, 1, 1, 'CDATA before root');
  Bad('<r><?xml version="1.0"?></r>', xecSyntax, 1, 4, 'declaration in content');
  Bad(' <?xml version="1.0"?><r/>', xecSyntax, 1, 2, 'declaration after white space');
  Bad('<!--c--><?xml version="1.0"?><r/>', xecSyntax, 1, 9, 'declaration after comment');
  Bad('<r><?XmL x?></r>', xecSyntax, 1, 4, 'reserved PI target');
  Bad('<r><?p:x y?></r>', xecNamespace, 1, 7, 'colon in PI target');
  Bad('<r><?pi x</r>', xecSyntax, 1, 4, 'unterminated PI');
  Bad('<r><?pi?x?></r>', xecSyntax, 1, 8, 'PI target followed by ?');
  Bad('<r><? x?></r>', xecSyntax, 1, 6, 'PI without target');
  Bad('<?xml version="1.0"?><?xml version="1.0"?><r/>', xecSyntax, 1, 22, 'second declaration');
end;

procedure TestDocTypes;
begin
  Bad('<r><!DOCTYPE r></r>', xecSyntax, 1, 4, 'DOCTYPE in content');
  Bad('<!DOCTYPE r><!DOCTYPE r><r/>', xecSyntax, 1, 13, 'second DOCTYPE');
  Bad('<r/><!DOCTYPE r>', xecSyntax, 1, 5, 'DOCTYPE after root');
  Bad('<!DOCTYPE r [ <r/>', xecSyntax, 1, 1, 'unterminated internal subset');
  Bad('<!DOCTYPE r SYSTEM "x><r/>', xecSyntax, 1, 1, 'unterminated literal');
  Bad('<!DOCTYPEr><r/>', xecSyntax, 1, 10, 'no space after DOCTYPE');
  Bad('<!DOCTYPE r ]><r/>', xecSyntax, 1, 13, '] outside subset');
  Bad('<!doctype r><r/>', xecSyntax, 1, 1, 'lowercase doctype');
end;

procedure TestNamespaceErrors;
begin
  Bad('<a:b:c/>', xecNamespace, 1, 5, 'two colons');
  Bad('<:a/>', xecNamespace, 1, 2, 'empty prefix');
  Bad('<a:/>', xecNamespace, 1, 3, 'empty local name');
  Bad('<a:1 xmlns:a="urn:a"/>', xecNamespace, 1, 4, 'local name starting with a digit');
  Bad('<p:r/>', xecNamespace, 1, 2, 'undeclared element prefix');
  Bad('<r p:a="1"/>', xecNamespace, 1, 4, 'undeclared attribute prefix');
  Bad('<r xmlns:p=""/>', xecNamespace, 1, 4, 'prefix bound to empty URI');
  Bad('<r xmlns:xmlns="urn:x"/>', xecNamespace, 1, 4, 'declaring xmlns');
  Bad('<r xmlns:xml="urn:x"/>', xecNamespace, 1, 4, 'rebinding xml');
  Bad('<r xmlns:p="http://www.w3.org/XML/1998/namespace"/>', xecNamespace, 1, 4, 'binding the XML namespace');
  Bad('<r xmlns:p="http://www.w3.org/2000/xmlns/"/>', xecNamespace, 1, 4, 'binding the xmlns namespace');
  Bad('<r xmlns="http://www.w3.org/2000/xmlns/"/>', xecNamespace, 1, 4, 'xmlns namespace as default');
  Bad('<r xmlns="http://www.w3.org/XML/1998/namespace"/>', xecNamespace, 1, 4, 'XML namespace as default');
  Bad('<xmlns:r/>', xecNamespace, 1, 2, 'element prefix xmlns');
  Bad('<r xmlns:a="urn:x" xmlns:b="urn:x" a:z="1" b:z="2"/>', xecNamespace, 1, 44, 'expanded duplicate');
  Bad('<r xmlns:p="urn:p"><p:a/></r><p:b/>', xecSyntax, 1, 30, 'second root with prefix');
  Bad('<a xmlns:p="urn:p"></a><p:b/>', xecSyntax, 1, 24, 'binding out of scope (two roots)');
  Bad('<r><a xmlns:p="urn:p"/><p:b/></r>', xecNamespace, 1, 25, 'binding out of scope');
end;

procedure Register;
begin
  RegisterTest('ReaderErrors.DocumentStructure', TestDocumentStructure);
  RegisterTest('ReaderErrors.Attributes', TestAttributes);
  RegisterTest('ReaderErrors.References', TestReferences);
  RegisterTest('ReaderErrors.Characters', TestCharacters);
  RegisterTest('ReaderErrors.CommentsCDataPis', TestCommentsCDataPis);
  RegisterTest('ReaderErrors.DocTypes', TestDocTypes);
  RegisterTest('ReaderErrors.NamespaceErrors', TestNamespaceErrors);
end;

end.
