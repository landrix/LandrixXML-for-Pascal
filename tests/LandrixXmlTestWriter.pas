{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Tests for LandrixXmlWriter: exact output, escaping and read-back through
  LandrixXmlReader, namespaces, state errors, atomicity of rejected calls,
  indentation, base64, stream mode. Also the base64 encoder and name
  checks of LandrixXmlBase. }

unit LandrixXmlTestWriter;

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
  LandrixXmlWriter,
  LandrixXmlTestFramework,
  LandrixXmlTestReader;

const
  Decl = '<?xml version="1.0" encoding="UTF-8"?>' + #10;

{ ASCII/byte literal as UTF-8 without any code page conversion. }
function U(const S: AnsiString): TLandrixXmlUtf8;
begin
  Result := '';
  SetLength(Result, Length(S));
  if S <> '' then
    Move(PAnsiChar(S)^, PAnsiChar(Result)^, Length(S));
end;

function Num(I: Integer): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(IntToStr(I));
end;

function Raw(const S: TLandrixXmlUtf8): AnsiString;
begin
  Result := '';
  SetLength(Result, Length(S));
  if S <> '' then
    Move(PAnsiChar(S)^, PAnsiChar(Result)^, Length(S));
end;

{ All text and CDATA content of a document, read back with the reader. }
function ReadText(const Xml: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  Reader: TLandrixXmlReader;
begin
  Result := '';
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromUtf8(Xml);
    while Reader.Read do
      if Reader.TokenType in [xttText, xttCData] then
        Result := Result + Reader.ValueUtf8;
  finally
    Reader.Free;
  end;
end;

{ Value of the root element's attribute with this local name. }
function ReadAttr(const Xml, LocalName: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  Reader: TLandrixXmlReader;
  I: Integer;
begin
  Result := '';
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromUtf8(Xml);
    Reader.Read;
    for I := 0 to Reader.AttributeCount - 1 do
      if Reader.AttributeLocalNameUtf8(I) = LocalName then
        Result := Reader.AttributeValueUtf8(I);
  finally
    Reader.Free;
  end;
end;

procedure Exec(W: TLandrixXmlWriter; const Op: string; const A, B, C, D: TLandrixXmlUtf8);
begin
  if Op = 'start' then
    W.StartElement(A)
  else if Op = 'startns' then
    W.StartElementNs(A, B, C)
  else if Op = 'end' then
    W.EndElement
  else if Op = 'attr' then
    W.AttributeUtf8(A, B)
  else if Op = 'attrns' then
    W.AttributeNsUtf8(A, B, C, D)
  else if Op = 'decl' then
    W.DeclareNamespace(A, B)
  else if Op = 'elem' then
    W.ElementUtf8(A, B)
  else if Op = 'elemns' then
    W.ElementNsUtf8(A, B, C, D)
  else if Op = 'text' then
    W.TextUtf8(A)
  else if Op = 'cdata' then
    W.CDataUtf8(A)
  else if Op = 'comment' then
    W.CommentUtf8(A)
  else if Op = 'pi' then
    W.ProcessingInstructionUtf8(A, B)
  else if Op = 'doctype' then
    W.DocumentType(A, B)
  else if Op = 'startdoc' then
    W.StartDocument
  else if Op = 'enddoc' then
    W.EndDocument
  else
    Fail('unknown test operation ' + Op);
end;

{ Op must raise ELandrixXmlError with Code and leave the writer unchanged. }
procedure ExpectError(W: TLandrixXmlWriter; const Op: string;
  const A, B, C, D: TLandrixXmlUtf8; Code: TLandrixXmlErrorCode; const Name: string);
var
  Before: Int64;
  Depth: Integer;
begin
  Before := W.BytesWritten;
  Depth := W.Depth;
  try
    Exec(W, Op, A, B, C, D);
    FailNotRaised('ELandrixXmlError for ' + Name);
  except
    on E: ELandrixXmlError do
      CheckEquals(Ord(Code), Ord(E.Code), Name + ' (error code; message: ' + E.Message + ')');
  end;
  CheckEqualsInt64(Before, W.BytesWritten, Name + ' (output unchanged)');
  CheckEquals(Depth, W.Depth, Name + ' (depth unchanged)');
end;

procedure Err(W: TLandrixXmlWriter; const Op: string; const A: TLandrixXmlUtf8;
  Code: TLandrixXmlErrorCode; const Name: string);
begin
  ExpectError(W, Op, A, '', '', '', Code, Name);
end;

procedure Err2(W: TLandrixXmlWriter; const Op: string; const A, B: TLandrixXmlUtf8;
  Code: TLandrixXmlErrorCode; const Name: string);
begin
  ExpectError(W, Op, A, B, '', '', Code, Name);
end;

{ --- base unit helpers -------------------------------------------------------- }

function Base64Of(const S: AnsiString): TLandrixXmlUtf8;
var
  Buf: TLandrixXmlBuffer;
begin
  Buf := TLandrixXmlBuffer.Create;
  try
    if S <> '' then
      LandrixXmlBase64Encode(PAnsiChar(S)^, Length(S), Buf);
    Result := Buf.AsUtf8;
  finally
    Buf.Free;
  end;
end;

procedure TestBase64Encode;
begin
  { RFC 4648 test vectors }
  CheckEqualsUtf8('', Base64Of(''), 'empty');
  CheckEqualsUtf8('Zg==', Base64Of('f'), 'f');
  CheckEqualsUtf8('Zm8=', Base64Of('fo'), 'fo');
  CheckEqualsUtf8('Zm9v', Base64Of('foo'), 'foo');
  CheckEqualsUtf8('Zm9vYg==', Base64Of('foob'), 'foob');
  CheckEqualsUtf8('Zm9vYmE=', Base64Of('fooba'), 'fooba');
  CheckEqualsUtf8('Zm9vYmFy', Base64Of('foobar'), 'foobar');
  CheckEqualsUtf8('AP/+', Base64Of(Bytes([$00, $FF, $FE])), 'high bytes');
  CheckEqualsUtf8('+/8=', Base64Of(Bytes([$FB, $FF])), 'plus and slash');
end;

procedure TestNameChecks;
begin
  CheckEquals(-1, LandrixXmlCheckName('abc', 3), 'plain name');
  CheckEquals(-1, LandrixXmlCheckName('_a.b-c:d9', 9), 'name characters');
  CheckEquals(0, LandrixXmlCheckName('', 0), 'empty name');
  CheckEquals(0, LandrixXmlCheckName('1a', 2), 'digit first');
  CheckEquals(0, LandrixXmlCheckName('-a', 2), 'hyphen first');
  CheckEquals(1, LandrixXmlCheckName('a b', 3), 'space');
  CheckEquals(-1, LandrixXmlCheckName(PAnsiChar(Raw(Utf8Bytes([$C3, $A4, $C3, $9F]))), 4),
    'umlauts');
  CheckEquals(1, LandrixXmlCheckName(PAnsiChar(Raw(Utf8Bytes([$61, $C3]))), 2),
    'truncated UTF-8');
  CheckEquals(0, LandrixXmlCheckName(PAnsiChar(Raw(Utf8Bytes([$CC, $80]))), 2),
    'combining mark first');
  Check(LandrixXmlIsNameStartChar($10000), 'U+10000 starts a name');
  Check(not LandrixXmlIsNameStartChar($F0000), 'U+F0000 does not');
  Check(LandrixXmlIsNameChar($B7), 'U+00B7 is a name character');
  Check(not LandrixXmlIsNameStartChar($B7), 'U+00B7 does not start a name');
end;

{ --- output -------------------------------------------------------------------- }

procedure TestBasicDocument;
var
  W: TLandrixXmlWriter;
begin
  W := TLandrixXmlWriter.Create;
  try
    W.StartElement('root');
    W.Attribute('a', '1');
    W.AttributeUtf8('b', 'two');
    W.Element('x', 'text');
    W.StartElement('empty');
    W.EndElement;
    W.ElementUtf8('e', '');
    W.StartElement('n');
    W.StartElement('m');
    W.TextUtf8('deep');
    W.EndElement;
    W.EndElement;
    W.EndElement;
    W.EndDocument;
    CheckEqualsUtf8(U(Decl + '<root a="1" b="two"><x>text</x><empty/><e/><n><m>deep</m></n></root>'),
      W.AsUtf8, 'document');
    CheckEqualsInt64(Length(W.AsUtf8), W.BytesWritten, 'BytesWritten');
    CheckEqualsStr(
      '<root a="1" b="two"><x>T"text"</x><empty/></empty><e/></e><n><m>T"deep"</m></n></root>',
      DumpTokens(Raw(W.AsUtf8)), 'read back');
  finally
    W.Free;
  end;
end;

procedure TestDeclarationOptions;
var
  W: TLandrixXmlWriter;
begin
  W := TLandrixXmlWriter.Create;
  try
    W.WriteDeclaration := False;
    W.ElementUtf8('r', '');
    W.EndDocument;
    CheckEqualsUtf8('<r/>', W.AsUtf8, 'no declaration');

    W.Clear;
    W.WriteDeclaration := True;
    W.WriteBom := True;
    W.Standalone := xsaYes;
    W.ElementUtf8('r', '');
    W.EndDocument;
    CheckEqualsUtf8(U(#$EF#$BB#$BF'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'#10'<r/>'),
      W.AsUtf8, 'BOM and standalone');
    CheckEqualsStr('<r/></r>', DumpTokens(Raw(W.AsUtf8)), 'BOM output reads back');

    W.Clear;
    W.WriteBom := False;
    W.Standalone := xsaNo;
    W.LineBreak := xlbCRLF;
    W.StartDocument;
    Err(W, 'startdoc', '', xecInvalidOperation, 'StartDocument twice');
    W.ElementUtf8('r', '');
    W.EndDocument;
    CheckEqualsUtf8(U('<?xml version="1.0" encoding="UTF-8" standalone="no"?>'#13#10'<r/>'),
      W.AsUtf8, 'explicit StartDocument, CRLF');

    W.Clear;
    W.Standalone := xsaOmit;
    W.LineBreak := xlbLF;
    W.StartElement('r');
    try
      W.Indent := True;
      FailNotRaised('ELandrixXmlError for option change');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecInvalidOperation), Ord(E.Code), 'option change after start');
    end;
    try
      W.WriteBom := True;
      FailNotRaised('ELandrixXmlError for BOM change');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecInvalidOperation), Ord(E.Code), 'BOM change after start');
    end;
    Err(W, 'startdoc', '', xecInvalidOperation, 'StartDocument after output');
    W.Clear;
    try
      W.IndentString := ' x';
      FailNotRaised('ELandrixXmlError for IndentString');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecInvalidArgument), Ord(E.Code), 'IndentString with a letter');
    end;
  finally
    W.Free;
  end;
end;

procedure TestTextEscaping;
var
  W: TLandrixXmlWriter;
  Value: TLandrixXmlUtf8;
begin
  Value := U('a&b<c>d"e''f'#9'g'#10'h'#13'i'#13#10'j]]>k');
  W := TLandrixXmlWriter.Create;
  try
    W.WriteDeclaration := False;
    W.StartElement('r');
    W.TextUtf8(Value);
    W.EndElement;
    W.EndDocument;
    CheckEqualsUtf8(U('<r>a&amp;b&lt;c&gt;d"e''f'#9'g'#10'h&#13;i&#13;'#10'j]]&gt;k</r>'),
      W.AsUtf8, 'escaped text');
    CheckEqualsUtf8(Value, ReadText(W.AsUtf8), 'text reads back unchanged');
  finally
    W.Free;
  end;
end;

procedure TestAttributeEscaping;
var
  W: TLandrixXmlWriter;
  Value: TLandrixXmlUtf8;
begin
  Value := U('x&<>"'''#9'a'#10'b'#13'c'#13#10'd  e');
  W := TLandrixXmlWriter.Create;
  try
    W.WriteDeclaration := False;
    W.StartElement('r');
    W.AttributeUtf8('v', Value);
    W.EndElement;
    W.EndDocument;
    CheckEqualsUtf8(U('<r v="x&amp;&lt;&gt;&quot;''&#9;a&#10;b&#13;c&#13;&#10;d  e"/>'),
      W.AsUtf8, 'escaped attribute');
    CheckEqualsUtf8(Value, ReadAttr(W.AsUtf8, 'v'), 'attribute reads back unchanged');
  finally
    W.Free;
  end;
end;

procedure TestValueVariants;
var
  W: TLandrixXmlWriter;
  Expected: TLandrixXmlUtf8;
begin
  { U+00E4, U+20AC, U+1F600 }
  Expected := Utf8Bytes([$C3, $A4, $E2, $82, $AC, $F0, $9F, $98, $80]);
  W := TLandrixXmlWriter.Create;
  try
    W.WriteDeclaration := False;
    W.StartElement('r');
    W.AttributeW('w', Wide([$E4, $20AC, $D83D, $DE00]));
    W.Attribute('n', 'native');
    W.ElementW('a', Wide([$E4, $20AC, $D83D, $DE00]));
    W.ElementUtf8('b', Expected);
    W.Element('c', 'native');
    W.StartElement('d');
    W.TextW(Wide([$E4]));
    W.Text('x');
    W.CDataW(Wide([$20AC]));
    W.CData('y');
    W.CommentW(Wide([$E4]));
    W.Comment('z');
    W.ProcessingInstructionW('p', Wide([$E4]));
    W.ProcessingInstruction('q', 'v');
    W.EndElement;
    W.EndElement;
    W.EndDocument;
    CheckEqualsUtf8(U('<r w="') + Expected + U('" n="native"><a>') + Expected + U('</a><b>') +
      Expected + U('</b><c>native</c><d>') + Utf8Bytes([$C3, $A4]) + U('x<![CDATA[') +
      Utf8Bytes([$E2, $82, $AC]) + U(']]><![CDATA[y]]><!--') + Utf8Bytes([$C3, $A4]) +
      U('--><!--z--><?p ') + Utf8Bytes([$C3, $A4]) + U('?><?q v?></d></r>'),
      W.AsUtf8, 'all value variants');
    CheckEqualsWide(Wide([$3C, $72]), Copy(W.AsW, 1, 2), 'AsW');
    CheckEqualsStr('<r', Copy(W.AsString, 1, 2), 'AsString');
  finally
    W.Free;
  end;
end;

procedure TestInvalidCharacters;
var
  W: TLandrixXmlWriter;
begin
  W := TLandrixXmlWriter.Create;
  try
    W.WriteDeclaration := False;
    W.StartElement('r');
    W.AttributeUtf8('ok', 'fine');
    Err2(W, 'attr', 'a', U('x'#0'y'), xecInvalidChar, 'NUL in attribute');
    Err2(W, 'attr', 'a', U('x'#1), xecInvalidChar, 'U+0001 in attribute');
    W.TextUtf8('t');
    Err(W, 'text', U(#1), xecInvalidChar, 'U+0001 in text');
    Err(W, 'text', U(#$1F), xecInvalidChar, 'U+001F in text');
    Err(W, 'text', U('ab') + Utf8Bytes([$C3]), xecInvalidUnicode, 'truncated UTF-8');
    Err(W, 'text', Utf8Bytes([$C0, $80]), xecInvalidUnicode, 'overlong NUL');
    Err(W, 'text', Utf8Bytes([$ED, $A0, $80]), xecInvalidUnicode, 'encoded surrogate');
    Err(W, 'text', Utf8Bytes([$EF, $BF, $BE]), xecInvalidChar, 'U+FFFE');
    Err(W, 'text', Utf8Bytes([$EF, $BF, $BF]), xecInvalidChar, 'U+FFFF');
    Err(W, 'cdata', U(#2), xecInvalidChar, 'U+0002 in CDATA');
    Err(W, 'comment', U(#3), xecInvalidChar, 'U+0003 in comment');
    Err2(W, 'pi', 't', U(#4), xecInvalidChar, 'U+0004 in PI');
    Err2(W, 'elem', 'e', U(#5), xecInvalidChar, 'U+0005 in element value');
    try
      W.TextW(Wide([$61, $D800]));
      FailNotRaised('ELandrixXmlError for unpaired surrogate');
    except
      on E: ELandrixXmlError do
      begin
        CheckEquals(Ord(xecInvalidUnicode), Ord(E.Code), 'unpaired surrogate (code)');
        CheckEqualsInt64(1, E.Offset, 'unpaired surrogate (offset in code units)');
      end;
    end;
    try
      W.TextUtf8(U('abc'#1));
      FailNotRaised('ELandrixXmlError for offset');
    except
      on E: ELandrixXmlError do
      begin
        CheckEqualsInt64(3, E.Offset, 'offset of the bad character');
        Check(Pos('/r', E.Message) > 0, 'message names the element path: ' + E.Message);
      end;
    end;
    W.EndElement;
    W.EndDocument;
    CheckEqualsUtf8('<r ok="fine">t</r>', W.AsUtf8, 'rejected calls left no trace');
  finally
    W.Free;
  end;
end;

procedure TestCDataCommentPi;
var
  W: TLandrixXmlWriter;
begin
  W := TLandrixXmlWriter.Create;
  try
    W.WriteDeclaration := False;
    W.CommentUtf8(' before ');
    W.ProcessingInstructionUtf8('style', 'href="a.css"');
    W.StartElement('r');
    W.CDataUtf8('a<&>b');
    W.CDataUtf8('');
    W.CommentUtf8('');
    W.ProcessingInstructionUtf8('t', '');
    Err(W, 'cdata', ']]>', xecWrite, ']]> in CDATA');
    Err(W, 'cdata', U('a'#13'b'), xecWrite, 'CR in CDATA');
    Err(W, 'comment', 'a--b', xecWrite, '-- in comment');
    Err(W, 'comment', 'a-', xecWrite, 'comment ending in -');
    Err(W, 'comment', U('a'#13), xecWrite, 'CR in comment');
    Err2(W, 'pi', 'xml', '', xecWrite, 'PI target xml');
    Err2(W, 'pi', 'XmL', '', xecWrite, 'PI target XmL');
    Err2(W, 'pi', 'a:b', '', xecNamespace, 'PI target with colon');
    Err2(W, 'pi', '1a', '', xecWrite, 'PI target not a name');
    Err2(W, 'pi', 't', 'a?>b', xecWrite, '?> in PI data');
    Err2(W, 'pi', 't', ' a', xecWrite, 'PI data with leading space');
    Err2(W, 'pi', 't', U('a'#13'b'), xecWrite, 'CR in PI data');
    W.EndElement;
    W.CommentUtf8('after');
    Err(W, 'cdata', 'x', xecInvalidOperation, 'CDATA after the root element');
    W.EndDocument;
    CheckEqualsUtf8('<!-- before --><?style href="a.css"?><r><![CDATA[a<&>b]]><![CDATA[]]>' +
      '<!----><?t?></r><!--after-->', W.AsUtf8, 'output');
    CheckEqualsStr('!" before "?style"href="a.css""<r>C"a<&>b"C""!""?t""</r>!"after"',
      DumpTokens(Raw(W.AsUtf8)), 'read back');
  finally
    W.Free;
  end;
end;

procedure TestDocumentType;
var
  W: TLandrixXmlWriter;
begin
  W := TLandrixXmlWriter.Create;
  try
    W.WriteDeclaration := False;
    Err2(W, 'doctype', 'r', 'SYSTEM "r.dtd"', xecWrite, 'content without leading space');
    Err2(W, 'doctype', '1r', '', xecWrite, 'invalid name');
    Err2(W, 'doctype', 'r', ' [', xecWrite, 'unterminated subset');
    Err2(W, 'doctype', 'r', ' ]', xecWrite, 'stray ]');
    Err2(W, 'doctype', 'r', ' SYSTEM "a', xecWrite, 'unterminated literal');
    Err2(W, 'doctype', 'r', ' x>y', xecWrite, '> outside the subset');
    Err2(W, 'doctype', 'r', ' <x', xecWrite, '< outside the subset');
    Err2(W, 'doctype', 'r', ' [<!-- a', xecWrite, 'unterminated comment');
    Err2(W, 'doctype', 'r', ' [<?p a', xecWrite, 'unterminated PI');
    Err2(W, 'doctype', 'r', U(' SYSTEM "a'#13'"'), xecWrite, 'CR in content');
    W.DocumentType('r', ' SYSTEM "r.dtd" [<!ENTITY e "a>b"><!-- ] > --><?p ]>?>]');
    Err2(W, 'doctype', 'r', '', xecInvalidOperation, 'second DOCTYPE');
    W.ElementUtf8('r', '');
    W.EndDocument;
    CheckEqualsUtf8('<!DOCTYPE r SYSTEM "r.dtd" [<!ENTITY e "a>b"><!-- ] > --><?p ]>?>]><r/>',
      W.AsUtf8, 'output');
    CheckEqualsStr('Dr<r/></r>', DumpTokens(Raw(W.AsUtf8)), 'read back');
    W.Clear;
    W.ElementUtf8('r', '');
    Err2(W, 'doctype', 'r', '', xecInvalidOperation, 'DOCTYPE after the root');
  finally
    W.Free;
  end;
end;

{ --- namespaces ---------------------------------------------------------------- }

procedure TestNamespacesLexical;
var
  W: TLandrixXmlWriter;
begin
  W := TLandrixXmlWriter.Create;
  try
    W.WriteDeclaration := False;
    W.StartElement('p:r');
    W.DeclareNamespace('p', 'urn:p');
    W.Attribute('xmlns', 'urn:default');
    W.AttributeUtf8('xml:lang', 'de');
    W.ElementUtf8('p:a', '1');
    W.ElementUtf8('b', '2');
    W.StartElement('q:c');
    { the prefix is checked when the start tag closes: the next call fails
      and can be retried after declaring it }
    Err(W, 'text', 'x', xecNamespace, 'undeclared prefix');
    Err(W, 'end', '', xecNamespace, 'undeclared prefix on EndElement');
    W.AttributeUtf8('xmlns:q', 'urn:q');
    W.TextUtf8('x');
    W.EndElement;
    Err2(W, 'elem', 'q:d', '', xecNamespace, 'prefix out of scope');
    W.EndElement;
    W.EndDocument;
    CheckEqualsUtf8('<p:r xmlns:p="urn:p" xmlns="urn:default" xml:lang="de"><p:a>1</p:a>' +
      '<b>2</b><q:c xmlns:q="urn:q">x</q:c></p:r>', W.AsUtf8, 'output');
    CheckEqualsStr('<p:r{urn:p} xmlns:p{http://www.w3.org/2000/xmlns/}="urn:p" ' +
      'xmlns{http://www.w3.org/2000/xmlns/}="urn:default" ' +
      'xml:lang{http://www.w3.org/XML/1998/namespace}="de">' +
      '<p:a{urn:p}>T"1"</p:a{urn:p}><b{urn:default}>T"2"</b{urn:default}>' +
      '<q:c{urn:q} xmlns:q{http://www.w3.org/2000/xmlns/}="urn:q">T"x"</q:c{urn:q}>' +
      '</p:r{urn:p}>', DumpTokens(Raw(W.AsUtf8)), 'read back');
  finally
    W.Free;
  end;
end;

procedure TestNamespacesAutomatic;
var
  W: TLandrixXmlWriter;
begin
  W := TLandrixXmlWriter.Create;
  try
    W.WriteDeclaration := False;
    W.StartElementNs('urn:inv', '', 'Invoice');
    W.DeclareNamespace('cbc', 'urn:cbc');
    W.ElementNsUtf8('urn:cbc', 'cbc', 'ID', '1');
    W.ElementNsUtf8('urn:inv', '', 'Same', '');
    W.ElementNsUtf8('urn:other', 'cbc', 'Shadow', '');
    W.ElementNsUtf8('urn:x', 'x', 'New', '');
    W.ElementNsUtf8('', '', 'NoNs', '');
    W.StartElementNs('urn:inv', '', 'Line');
    W.AttributeNsUtf8('urn:a', 'a', 'attr', 'v');
    W.AttributeNsUtf8('', '', 'plain', 'w');
    W.AttributeNsUtf8(LandrixXmlNamespaceXml, 'xml', 'lang', 'en');
    W.EndElement;
    W.EndElement;
    W.EndDocument;
    CheckEqualsUtf8('<Invoice xmlns="urn:inv" xmlns:cbc="urn:cbc"><cbc:ID>1</cbc:ID><Same/>' +
      '<cbc:Shadow xmlns:cbc="urn:other"/><x:New xmlns:x="urn:x"/><NoNs xmlns=""/>' +
      '<Line xmlns:a="urn:a" a:attr="v" plain="w" xml:lang="en"/></Invoice>', W.AsUtf8, 'output');
    CheckEqualsStr('<Invoice{urn:inv} xmlns{http://www.w3.org/2000/xmlns/}="urn:inv" ' +
      'xmlns:cbc{http://www.w3.org/2000/xmlns/}="urn:cbc">' +
      '<cbc:ID{urn:cbc}>T"1"</cbc:ID{urn:cbc}><Same{urn:inv}/></Same{urn:inv}>' +
      '<cbc:Shadow{urn:other} xmlns:cbc{http://www.w3.org/2000/xmlns/}="urn:other"/>' +
      '</cbc:Shadow{urn:other}>' +
      '<x:New{urn:x} xmlns:x{http://www.w3.org/2000/xmlns/}="urn:x"/></x:New{urn:x}>' +
      '<NoNs xmlns{http://www.w3.org/2000/xmlns/}=""/></NoNs>' +
      '<Line{urn:inv} xmlns:a{http://www.w3.org/2000/xmlns/}="urn:a" a:attr{urn:a}="v" ' +
      'plain="w" xml:lang{http://www.w3.org/XML/1998/namespace}="en"/></Line{urn:inv}>' +
      '</Invoice{urn:inv}>',
      DumpTokens(Raw(W.AsUtf8)), 'read back');
  finally
    W.Free;
  end;
end;

procedure TestNamespaceRules;
var
  W: TLandrixXmlWriter;
  I: Integer;
begin
  W := TLandrixXmlWriter.Create;
  try
    W.WriteDeclaration := False;
    Err(W, 'start', 'xmlns:a', xecNamespace, 'element prefix xmlns');
    Err(W, 'start', 'a:b:c', xecNamespace, 'two colons');
    Err(W, 'start', ':a', xecNamespace, 'empty prefix');
    Err(W, 'start', 'a:', xecNamespace, 'empty local part');
    Err(W, 'start', 'a:1', xecNamespace, 'local part starting with a digit');
    Err(W, 'start', '1a', xecWrite, 'name starting with a digit');
    Err(W, 'start', '', xecWrite, 'empty name');
    Err(W, 'start', 'a b', xecWrite, 'name with a space');
    ExpectError(W, 'startns', 'urn:x', 'xml', 'a', '', xecNamespace, 'prefix xml with another URI');
    ExpectError(W, 'startns', LandrixXmlNamespaceXml, '', 'a', '', xecNamespace,
      'XML namespace without prefix xml');
    ExpectError(W, 'startns', LandrixXmlNamespaceXmlns, 'p', 'a', '', xecNamespace,
      'xmlns namespace');
    ExpectError(W, 'startns', '', 'p', 'a', '', xecInvalidArgument, 'prefix without URI');
    ExpectError(W, 'startns', 'urn:x', 'p', 'a:b', '', xecNamespace, 'colon in local name');
    W.StartElement('r');
    Err2(W, 'decl', 'xmlns', 'urn:x', xecNamespace, 'declare xmlns');
    Err2(W, 'decl', 'xml', 'urn:x', xecNamespace, 'rebind xml');
    Err2(W, 'decl', 'p', '', xecNamespace, 'prefix to empty URI');
    Err2(W, 'decl', 'p', LandrixXmlNamespaceXml, xecNamespace, 'bind the XML namespace');
    Err2(W, 'decl', '', LandrixXmlNamespaceXmlns, xecNamespace, 'default to xmlns namespace');
    Err2(W, 'decl', 'a:b', 'urn:x', xecNamespace, 'prefix with colon');
    Err2(W, 'attr', 'xmlns:p', '', xecNamespace, 'xmlns:p attribute with empty URI');
    W.DeclareNamespace('xml', LandrixXmlNamespaceXml);
    W.DeclareNamespace('p', 'urn:p');
    Err2(W, 'decl', 'p', 'urn:p', xecWrite, 'duplicate declaration');
    Err2(W, 'attr', 'xmlns:p', 'urn:p', xecWrite, 'duplicate declaration as attribute');
    W.AttributeUtf8('a', '1');
    Err2(W, 'attr', 'a', '2', xecWrite, 'duplicate attribute');
    ExpectError(W, 'attrns', '', 'p', 'b', '1', xecInvalidArgument, 'attribute prefix without URI');
    ExpectError(W, 'attrns', 'urn:x', '', 'b', '1', xecInvalidArgument,
      'namespaced attribute without prefix');
    W.EndElement;
    W.EndDocument;
    CheckEqualsUtf8('<r xmlns:xml="http://www.w3.org/XML/1998/namespace" xmlns:p="urn:p" a="1"/>',
      W.AsUtf8, 'output');

    { duplicates after namespace resolution are found when the tag closes }
    W.Clear;
    W.StartElement('r');
    W.DeclareNamespace('a', 'urn:x');
    W.DeclareNamespace('b', 'urn:x');
    W.AttributeUtf8('a:x', '1');
    W.AttributeUtf8('b:x', '2');
    Err(W, 'end', '', xecNamespace, 'expanded duplicate');

    { conflicting requirements on one element }
    W.Clear;
    W.StartElementNs('urn:a', 'p', 'r');
    ExpectError(W, 'attrns', 'urn:b', 'p', 'x', '1', xecNamespace, 'prefix needed for two URIs');
    Err2(W, 'decl', 'p', 'urn:b', xecNamespace, 'declaration contradicts StartElementNs');
    Err2(W, 'decl', 'p', 'urn:a', xecWrite, 'second declaration of an automatic prefix');
    W.EndElement;
    W.Clear;
    W.StartElement('r');
    W.DeclareNamespace('p', 'urn:a');
    W.StartElementNs('urn:a', 'p', 'c');
    Err2(W, 'decl', 'p', 'urn:b', xecNamespace, 'declaration contradicts inherited binding');
    W.StartElement('d');
    W.AttributeNsUtf8('urn:a', 'p', 'x', '1');
    Err2(W, 'decl', 'p', 'urn:b', xecNamespace, 'declaration contradicts AttributeNs');

    { many attributes: the hashed duplicate checks }
    W.Clear;
    W.StartElement('r');
    for I := 1 to 40 do
      W.AttributeUtf8(U('a') + Num(I), '1');
    Err2(W, 'attr', 'a17', '1', xecWrite, 'duplicate among many attributes');
    for I := 1 to 20 do
      W.DeclareNamespace(U('p') + Num(I), U('urn:') + Num(I));
    W.DeclareNamespace('dup', 'urn:7');
    for I := 1 to 20 do
      W.AttributeUtf8(U('p') + Num(I) + U(':x'), '1');
    W.AttributeUtf8('dup:x', '1');
    Err(W, 'end', '', xecNamespace, 'expanded duplicate among many attributes');
  finally
    W.Free;
  end;
end;

{ --- state ------------------------------------------------------------------- }

procedure TestStateErrors;
var
  W: TLandrixXmlWriter;
begin
  W := TLandrixXmlWriter.Create;
  try
    W.WriteDeclaration := False;
    Err(W, 'end', '', xecInvalidOperation, 'EndElement without element');
    Err2(W, 'attr', 'a', '1', xecInvalidOperation, 'attribute without element');
    Err2(W, 'decl', 'p', 'urn:p', xecInvalidOperation, 'declaration without element');
    Err(W, 'enddoc', '', xecInvalidOperation, 'EndDocument without root');
    Err(W, 'text', 'x', xecWrite, 'text before the root');
    Err(W, 'cdata', 'x', xecInvalidOperation, 'CDATA before the root');
    W.TextUtf8(U(' '#10));
    W.StartElement('r');
    W.TextUtf8('x');
    Err2(W, 'attr', 'a', '1', xecInvalidOperation, 'attribute after content');
    Err2(W, 'decl', 'p', 'urn:p', xecInvalidOperation, 'declaration after content');
    Err(W, 'enddoc', '', xecInvalidOperation, 'EndDocument with open element');
    try
      W.AsUtf8;
      FailNotRaised('ELandrixXmlError for AsUtf8');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecInvalidOperation), Ord(E.Code), 'AsUtf8 before EndDocument');
    end;
    W.EndElement;
    Err(W, 'start', 's', xecInvalidOperation, 'second root');
    Err2(W, 'elem', 's', '', xecInvalidOperation, 'second root via Element');
    Err(W, 'text', 'x', xecWrite, 'text after the root');
    W.TextUtf8(U(#9#13#10' '));
    W.EndDocument;
    Err(W, 'text', ' ', xecInvalidOperation, 'text after EndDocument');
    Err(W, 'enddoc', '', xecInvalidOperation, 'EndDocument twice');
    CheckEqualsUtf8(U(' '#10'<r>x</r>'#9#13#10' '), W.AsUtf8, 'white space outside the root');
    W.Clear;
    W.ElementUtf8('again', '');
    W.EndDocument;
    CheckEqualsUtf8('<again/>', W.AsUtf8, 'reuse after Clear');
  finally
    W.Free;
  end;
end;

procedure TestAtomicElement;
var
  W: TLandrixXmlWriter;
begin
  W := TLandrixXmlWriter.Create;
  try
    { a failing first call must not even leave the declaration behind }
    Err2(W, 'elem', 'a', U('x'#1), xecInvalidChar, 'invalid value in the first call');
    CheckEqualsInt64(0, W.BytesWritten, 'nothing written, declaration included');
    W.Clear;
    W.WriteDeclaration := False;
    W.StartElement('r');
    W.DeclareNamespace('p', 'urn:p');
    Err2(W, 'elem', 'q:x', 'v', xecNamespace, 'Element with undeclared prefix');
    Err2(W, 'elem', 'x', U('v'#1), xecInvalidChar, 'Element with invalid value');
    ExpectError(W, 'elemns', '', 'p', 'x', 'v', xecInvalidArgument, 'ElementNs prefix without URI');
    W.ElementUtf8('p:x', 'v');
    W.EndElement;
    W.EndDocument;
    CheckEqualsUtf8('<r xmlns:p="urn:p"><p:x>v</p:x></r>', W.AsUtf8, 'failed Element calls left no trace');
  finally
    W.Free;
  end;
end;

{ --- indentation ---------------------------------------------------------------- }

procedure TestIndentation;
var
  W: TLandrixXmlWriter;
begin
  W := TLandrixXmlWriter.Create;
  try
    W.Indent := True;
    W.CommentUtf8('c');
    W.StartElement('r');
    W.StartElement('a');
    W.ElementUtf8('b', '1');
    W.ElementUtf8('c', '');
    W.EndElement;
    W.StartElement('m', True);
    W.TextUtf8('x');
    W.ElementUtf8('i', 'y');
    W.StartElement('k');
    W.ElementUtf8('l', '');
    W.EndElement;
    W.TextUtf8('z');
    W.EndElement;
    W.StartElement('t');
    W.TextUtf8('t1');
    W.ElementUtf8('u', 'v');
    W.EndElement;
    W.StartElement('p');
    W.AttributeUtf8('xml:space', 'preserve');
    W.StartElement('q');
    W.StartElement('d');
    W.AttributeUtf8('xml:space', 'default');
    W.ElementUtf8('s', '1');
    W.EndElement;
    W.EndElement;
    W.EndElement;
    W.CommentUtf8('in');
    W.EndElement;
    W.CommentUtf8('e');
    W.EndDocument;
    CheckEqualsUtf8(U(Decl +
      '<!--c-->'#10 +
      '<r>'#10 +
      '  <a>'#10 +
      '    <b>1</b>'#10 +
      '    <c/>'#10 +
      '  </a>'#10 +
      '  <m>x<i>y</i><k><l/></k>z</m>'#10 +
      '  <t>t1<u>v</u></t>'#10 +
      '  <p xml:space="preserve"><q><d xml:space="default">'#10 +
      '        <s>1</s>'#10 +
      '      </d></q></p>'#10 +
      '  <!--in-->'#10 +
      '</r>'#10 +
      '<!--e-->'), W.AsUtf8, 'indented output');

    W.Clear;
    W.LineBreak := xlbCRLF;
    W.IndentString := #9;
    W.WriteDeclaration := False;
    W.StartElement('r');
    W.ElementUtf8('a', U('x'#10'y'));
    W.EndElement;
    W.EndDocument;
    CheckEqualsUtf8(U('<r>'#13#10#9'<a>x'#10'y</a>'#13#10'</r>'), W.AsUtf8,
      'CRLF and TAB; line breaks in values unchanged');
  finally
    W.Free;
  end;
end;

{ --- base64 ------------------------------------------------------------------- }

procedure TestBase64Writer;
var
  W, W2: TLandrixXmlWriter;
  Data: AnsiString;
  M: TMemoryStream;
  I: Integer;
begin
  Data := '';
  SetLength(Data, 150001);
  for I := 1 to Length(Data) do
    Data[I] := AnsiChar(I mod 251);
  W := TLandrixXmlWriter.Create;
  W2 := TLandrixXmlWriter.Create;
  M := TMemoryStream.Create;
  try
    W.WriteDeclaration := False;
    W.StartElement('r');
    W.Base64(PAnsiChar('foobar')^, 6);
    W.EndElement;
    W.EndDocument;
    CheckEqualsUtf8('<r>Zm9vYmFy</r>', W.AsUtf8, 'Base64');

    M.WriteBuffer(PAnsiChar(Data)^, Length(Data));
    M.Position := 0;
    W.Clear;
    W.StartElement('r');
    W.Base64FromStream(M);
    W.EndElement;
    W.EndDocument;
    W2.WriteDeclaration := False;
    W2.StartElement('r');
    W2.Base64(PAnsiChar(Data)^, Length(Data));
    W2.EndElement;
    W2.EndDocument;
    CheckEqualsUtf8(W2.AsUtf8, W.AsUtf8, 'Base64FromStream equals Base64 (several chunks)');
    CheckEquals(3 + ((Length(Data) + 2) div 3) * 4 + 4, Length(W.AsUtf8), 'encoded length');

    M.Position := 0;
    W.Clear;
    W.StartElement('r');
    W.Base64FromStream(M, 4);
    W.EndElement;
    W.EndDocument;
    CheckEqualsUtf8(U('<r>') + Base64Of(Copy(Data, 1, 4)) + U('</r>'), W.AsUtf8, 'Count');
    CheckEqualsInt64(4, M.Position, 'stream position after Count');

    W.Clear;
    W.StartElement('r');
    M.Position := M.Size - 2;
    try
      W.Base64FromStream(M, 10);
      FailNotRaised('ELandrixXmlError for short stream');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecInvalidArgument), Ord(E.Code), 'stream shorter than Count');
    end;
    W.EndElement;
    W.EndDocument;
    CheckEqualsUtf8('<r/>', W.AsUtf8, 'failed Base64FromStream left no trace (memory mode)');
    W.Clear;
    try
      W.Base64(PAnsiChar('x')^, 1);
      FailNotRaised('ELandrixXmlError for Base64 outside an element');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecInvalidOperation), Ord(E.Code), 'Base64 outside an element');
    end;
  finally
    M.Free;
    W2.Free;
    W.Free;
  end;
end;

{ --- stream mode -------------------------------------------------------------- }

procedure WriteBig(W: TLandrixXmlWriter);
var
  I: Integer;
begin
  W.StartElement('r');
  for I := 1 to 10000 do
    W.Element('item', IntToStr(I));
  W.EndElement;
  W.EndDocument;
end;

procedure TestStreamMode;
var
  W, Mem: TLandrixXmlWriter;
  M: TMemoryStream;
  S: TLandrixXmlUtf8;
  F: TFileStream;
  FileName: string;
  I: Integer;
  Raised: Boolean;
begin
  M := TMemoryStream.Create;
  Mem := TLandrixXmlWriter.Create;
  try
    W := TLandrixXmlWriter.Create(M);
    try
      W.ElementUtf8('small', '');
      CheckEqualsInt64(0, M.Size, 'small output stays buffered');
      try
        W.AsUtf8;
        FailNotRaised('ELandrixXmlError for AsUtf8 in stream mode');
      except
        on E: ELandrixXmlError do
          CheckEquals(Ord(xecInvalidOperation), Ord(E.Code), 'AsUtf8 in stream mode');
      end;
      W.Flush;
      Check(M.Size > 0, 'Flush writes buffered output');
      M.Clear;
      W.Clear;
      WriteBig(W);
      WriteBig(Mem);
      S := Mem.AsUtf8;
      CheckEqualsInt64(Length(S), M.Size, 'stream size');
      CheckEqualsInt64(Length(S), W.BytesWritten, 'BytesWritten in stream mode');
      Check((M.Size = Length(S)) and SameMemory(M.Memory, PAnsiChar(S), Length(S)),
        'stream content equals memory output');
    finally
      W.Free;
    end;
    M.Clear;
    W := TLandrixXmlWriter.Create(M);
    W.ElementUtf8('lost', '');
    W.Free;
    CheckEqualsInt64(0, M.Size, 'Destroy does not flush');
  finally
    Mem.Free;
    M.Free;
  end;

  { a file opened read-only refuses every write (like a full disk) }
  FileName := ExtractFilePath(ParamStr(0)) + 'writer-readonly.xml';
  F := TFileStream.Create(FileName, fmCreate);
  F.Free;
  F := TFileStream.Create(FileName, fmOpenRead);
  try
    W := TLandrixXmlWriter.Create(F);
    try
      W.StartElement('r');
      Raised := False;
      I := 0;
      try
        while I < 100000 do
        begin
          W.ElementUtf8('x', '0123456789');
          Inc(I);
        end;
      except
        on E: Exception do
          Raised := not (E is ELandrixXmlError);
      end;
      Check(Raised, 'the stream error surfaces as the stream''s exception');
      Err(W, 'text', 'x', xecInvalidOperation, 'writer unusable after a stream error');
      W.Clear;
      W.StartElement('r');
      CheckEquals(1, W.Depth, 'usable again after Clear');
    finally
      W.Free;
    end;
  finally
    F.Free;
    DeleteFile(FileName);
  end;
end;

procedure TestFiles;
var
  W: TLandrixXmlWriter;
  FileName: string;
  Reader: TLandrixXmlReader;
begin
  FileName := ExtractFilePath(ParamStr(0)) + 'writer-test.xml';
  W := TLandrixXmlWriter.CreateFile(FileName);
  try
    W.ElementUtf8('r', 'file');
    W.EndDocument;
  finally
    W.Free;
  end;
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromFile(FileName);
    Reader.Read;
    Reader.Read;
    CheckEqualsUtf8('file', Reader.ValueUtf8, 'CreateFile output');
  finally
    Reader.Free;
  end;
  W := TLandrixXmlWriter.Create;
  try
    W.ElementUtf8('r', 'saved');
    W.EndDocument;
    W.SaveToFile(FileName);
  finally
    W.Free;
  end;
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromFile(FileName);
    Reader.Read;
    Reader.Read;
    CheckEqualsUtf8('saved', Reader.ValueUtf8, 'SaveToFile output');
  finally
    Reader.Free;
  end;
  DeleteFile(FileName);
end;

procedure TestNoSilentRebinding;
var
  W: TLandrixXmlWriter;
begin
  W := TLandrixXmlWriter.Create;
  try
    W.WriteDeclaration := False;
    W.StartElement('root');
    W.DeclareNamespace('p', 'urn:a');
    W.StartElement('p:child');
    ExpectError(W, 'attrns', 'urn:b', 'p', 'x', '1', xecNamespace,
      'automatic declaration would move the element to another namespace');
    W.StartElement('c');
    W.AttributeUtf8('p:y', '1');
    ExpectError(W, 'attrns', 'urn:b', 'p', 'z', '1', xecNamespace,
      'automatic declaration would move an attribute to another namespace');
    W.AttributeNsUtf8('urn:a', 'p', 'z', '2');
    W.AttributeNsUtf8('urn:b', 'q', 'z', '3');
    W.EndElement;
    W.EndElement;
    W.EndElement;
    W.EndDocument;
    CheckEqualsUtf8('<root xmlns:p="urn:a"><p:child><c p:y="1" p:z="2" xmlns:q="urn:b" ' +
      'q:z="3"/></p:child></root>', W.AsUtf8, 'output');
  finally
    W.Free;
  end;
end;

procedure TestIndentationSafety;
var
  W: TLandrixXmlWriter;
begin
  W := TLandrixXmlWriter.Create;
  try
    W.Indent := True;
    W.WriteDeclaration := False;
    W.StartElement('r');
    { a rejected child must take its line break with it }
    Err2(W, 'elem', 'a', U('x'#1), xecInvalidChar, 'invalid child value');
    W.StartElement('p');
    W.ElementUtf8('b', 'bold');
    Err(W, 'text', ' tail', xecWrite, 'text after indented children');
    Err(W, 'cdata', 'tail', xecWrite, 'CDATA after indented children');
    try
      W.Base64(PAnsiChar('x')^, 1);
      FailNotRaised('ELandrixXmlError for base64 after indented children');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecWrite), Ord(E.Code), 'base64 after indented children');
    end;
    W.EndElement;
    W.StartElement('m', True);
    W.StartElement('d');
    W.AttributeUtf8('xml:space', 'default');
    W.ElementUtf8('s', '1');
    W.EndElement;
    W.TextUtf8('t');
    W.EndElement;
    W.StartElement('k');
    W.AttributeNsUtf8(LandrixXmlNamespaceXml, 'xml', 'space', 'preserve');
    W.ElementUtf8('s', '1');
    W.EndElement;
    W.EndElement;
    W.EndDocument;
    CheckEqualsUtf8(U('<r>'#10 +
      '  <p>'#10 +
      '    <b>bold</b>'#10 +
      '  </p>'#10 +
      '  <m><d xml:space="default"><s>1</s></d>t</m>'#10 +
      '  <k xml:space="preserve"><s>1</s></k>'#10 +
      '</r>'), W.AsUtf8, 'xml:space="default" does not cancel Mixed = True');
  finally
    W.Free;
  end;
end;

procedure TestBase64Edges;
var
  W: TLandrixXmlWriter;
  M: TMemoryStream;
begin
  W := TLandrixXmlWriter.Create;
  M := TMemoryStream.Create;
  try
    W.WriteDeclaration := False;
    try
      W.Base64(PAnsiChar('x')^, 0);
      FailNotRaised('ELandrixXmlError for empty base64 outside an element');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecInvalidOperation), Ord(E.Code), 'empty base64 outside an element');
    end;
    M.WriteBuffer(PAnsiChar('abc')^, 3);
    M.Position := 0;
    W.StartElement('r');
    W.Base64FromStream(M, 0);
    W.Base64(PAnsiChar('x')^, 0);
    try
      W.Base64FromStream(M, -2);
      FailNotRaised('ELandrixXmlError for Count = -2');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecInvalidArgument), Ord(E.Code), 'Count below -1');
    end;
    W.EndElement;
    W.EndDocument;
    CheckEqualsUtf8('<r/>', W.AsUtf8, 'empty base64 writes nothing');
    CheckEqualsInt64(0, M.Position, 'Count = 0 reads nothing');
  finally
    M.Free;
    W.Free;
  end;
end;

procedure TestManyAttributes;
var
  W: TLandrixXmlWriter;
  I: Integer;
  Reader: TLandrixXmlReader;
begin
  { the incremental hash keeps this linear; a rebuild per call took seconds }
  W := TLandrixXmlWriter.Create;
  try
    W.StartElement('r');
    for I := 1 to 20000 do
      W.AttributeUtf8(U('a') + Num(I), Num(I));
    Err2(W, 'attr', 'a19999', '1', xecWrite, 'duplicate among 20000 attributes');
    W.EndElement;
    W.EndDocument;
    Reader := TLandrixXmlReader.Create;
    try
      Reader.LoadFromUtf8(W.AsUtf8);
      Reader.Read;
      CheckEquals(20000, Reader.AttributeCount, 'attribute count');
      CheckEqualsUtf8('20000', Reader.AttributeValueUtf8(19999), 'last attribute');
    finally
      Reader.Free;
    end;
  finally
    W.Free;
  end;
end;

procedure Register;
begin
  RegisterTest('Base.Base64Encode', TestBase64Encode);
  RegisterTest('Base.NameChecks', TestNameChecks);
  RegisterTest('Writer.BasicDocument', TestBasicDocument);
  RegisterTest('Writer.DeclarationOptions', TestDeclarationOptions);
  RegisterTest('Writer.TextEscaping', TestTextEscaping);
  RegisterTest('Writer.AttributeEscaping', TestAttributeEscaping);
  RegisterTest('Writer.ValueVariants', TestValueVariants);
  RegisterTest('Writer.InvalidCharacters', TestInvalidCharacters);
  RegisterTest('Writer.CDataCommentPi', TestCDataCommentPi);
  RegisterTest('Writer.DocumentType', TestDocumentType);
  RegisterTest('Writer.NamespacesLexical', TestNamespacesLexical);
  RegisterTest('Writer.NamespacesAutomatic', TestNamespacesAutomatic);
  RegisterTest('Writer.NamespaceRules', TestNamespaceRules);
  RegisterTest('Writer.StateErrors', TestStateErrors);
  RegisterTest('Writer.AtomicElement', TestAtomicElement);
  RegisterTest('Writer.Indentation', TestIndentation);
  RegisterTest('Writer.Base64', TestBase64Writer);
  RegisterTest('Writer.StreamMode', TestStreamMode);
  RegisterTest('Writer.Files', TestFiles);
  RegisterTest('Writer.NoSilentRebinding', TestNoSilentRebinding);
  RegisterTest('Writer.IndentationSafety', TestIndentationSafety);
  RegisterTest('Writer.Base64Edges', TestBase64Edges);
  RegisterTest('Writer.ManyAttributes', TestManyAttributes);
end;

end.
