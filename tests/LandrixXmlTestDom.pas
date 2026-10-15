{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Tests for LandrixXmlDom: loading, navigation, search, text, whitespace
  options, building, moving and freeing nodes, saving and reloading. }

unit LandrixXmlTestDom;

{$I LandrixXml.inc}

interface

procedure Register;

implementation

uses
  SysUtils,
  Classes,
  LandrixXmlBase,
  LandrixXmlReader,
  LandrixXmlWriter,
  LandrixXmlDom,
  LandrixXmlTestFramework,
  LandrixXmlTestReader;

const
  Decl = '<?xml version="1.0" encoding="UTF-8"?>' + #10;

function U(const S: AnsiString): TLandrixXmlUtf8;
begin
  Result := '';
  SetLength(Result, Length(S));
  if S <> '' then
    Move(PAnsiChar(S)^, PAnsiChar(Result)^, Length(S));
end;

function Raw(const S: TLandrixXmlUtf8): AnsiString;
begin
  Result := '';
  SetLength(Result, Length(S));
  if S <> '' then
    Move(PAnsiChar(S)^, PAnsiChar(Result)^, Length(S));
end;

function Load(const Xml: AnsiString): TLandrixXmlDocument;
begin
  Result := TLandrixXmlDocument.Create;
  try
    Result.LoadFromBuffer(PAnsiChar(Xml)^, Length(Xml));
  except
    Result.Free;
    raise;
  end;
end;

{ Compact dump of a subtree: <name(ns in braces) a="v">...</name>,
  T"..", C"..", !"..", ?t"..", Dname }
function Dump(N: TLandrixXmlNode): string;
var
  I: Integer;
begin
  case N.NodeType of
    xntDocument:
      begin
        Result := '';
        for I := 0 to N.ChildCount - 1 do
          Result := Result + Dump(N[I]);
      end;
    xntElement:
      begin
        Result := '<' + LandrixXmlEscapeForMessage(N.NameUtf8, MaxInt);
        if N.NamespaceUriUtf8 <> '' then
          Result := Result + '{' + LandrixXmlEscapeForMessage(N.NamespaceUriUtf8, MaxInt) + '}';
        for I := 0 to N.AttributeCount - 1 do
          Result := Result + ' ' + LandrixXmlEscapeForMessage(N.AttributeNameUtf8(I), MaxInt) +
            '="' + LandrixXmlEscapeForMessage(N.AttributeValueUtf8(I), MaxInt) + '"';
        Result := Result + '>';
        for I := 0 to N.ChildCount - 1 do
          Result := Result + Dump(N[I]);
        Result := Result + '</' + LandrixXmlEscapeForMessage(N.NameUtf8, MaxInt) + '>';
      end;
    xntText:
      Result := 'T"' + LandrixXmlEscapeForMessage(N.ValueUtf8, MaxInt) + '"';
    xntCData:
      Result := 'C"' + LandrixXmlEscapeForMessage(N.ValueUtf8, MaxInt) + '"';
    xntComment:
      Result := '!"' + LandrixXmlEscapeForMessage(N.ValueUtf8, MaxInt) + '"';
    xntProcessingInstruction:
      Result := '?' + LandrixXmlEscapeForMessage(N.NameUtf8, MaxInt) + '"' +
        LandrixXmlEscapeForMessage(N.ValueUtf8, MaxInt) + '"';
  else
    Result := 'D' + LandrixXmlEscapeForMessage(N.NameUtf8, MaxInt);
  end;
end;

procedure ExpectCode(Code: TLandrixXmlErrorCode; E: Exception; const Name: string);
begin
  Check(E is ELandrixXmlError, Name + ': ' + E.ClassName + ': ' + E.Message);
  CheckEquals(Ord(Code), Ord(ELandrixXmlError(E).Code), Name + ' (message: ' + E.Message + ')');
end;

const
  Sample =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'#10 +
    '<!-- head -->'#10 +
    '<!DOCTYPE inv>'#10 +
    '<inv:Invoice xmlns:inv="urn:inv" xmlns="urn:def" id="7">'#10 +
    '  <Line no="1"><Name>A &amp; B</Name><Qty>2</Qty></Line>'#10 +
    '  <Line no="2"><Name>C</Name><![CDATA[x<y]]></Line>'#10 +
    '  <?pi data?>'#10 +
    '  <inv:Note>mixed <b>bold</b> text<!-- c --></inv:Note>'#10 +
    '</inv:Invoice>'#10 +
    '<!-- tail -->';

{ --- loading and navigation ---------------------------------------------------- }

procedure TestLoadAndNavigate;
var
  Doc: TLandrixXmlDocument;
  Root, Line, N: TLandrixXmlNode;
begin
  Doc := Load(Sample);
  try
    CheckEquals(4, Doc.ChildCount, 'document children: comment, doctype, root, comment');
    CheckEquals(Ord(xntComment), Ord(Doc[0].NodeType), 'prolog comment');
    CheckEquals(Ord(xntDocumentType), Ord(Doc[1].NodeType), 'doctype');
    CheckEqualsUtf8('inv', Doc[1].NameUtf8, 'doctype name');
    Root := Doc.Root;
    Check(Root = Doc[2], 'Root is the document element');
    CheckEqualsUtf8('inv:Invoice', Root.NameUtf8, 'qualified name');
    CheckEqualsUtf8('inv', Root.PrefixUtf8, 'prefix');
    CheckEqualsUtf8('Invoice', Root.LocalNameUtf8, 'local name');
    CheckEqualsUtf8('urn:inv', Root.NamespaceUriUtf8, 'namespace');
    CheckEquals(4, Root.Line, 'line');
    CheckEquals(1, Root.Column, 'column');
    CheckEqualsUtf8('1.0', Doc.Version, 'version');
    CheckEqualsUtf8('yes', Doc.Standalone, 'standalone');
    CheckEquals(3, Root.AttributeCount, 'attributes including declarations');
    Check(Root.IsNamespaceDeclaration(0) and Root.IsNamespaceDeclaration(1), 'declarations');
    CheckEqualsUtf8('7', Root.AttributeValueUtf8('', 'id'), 'attribute by name');
    Line := Root.FirstChildElement;
    CheckEqualsUtf8('Line', Line.NameUtf8, 'first child element');
    CheckEqualsUtf8('urn:def', Line.NamespaceUriUtf8, 'default namespace');
    CheckEquals(5, Line.Line, 'line of a child');
    CheckEquals(3, Line.Column, 'column of a child');
    Check(Line.Parent = Root, 'parent');
    Check(Line.PreviousSibling.NodeType = xntText, 'white space before it is kept');
    CheckEquals(Line.IndexInParent, Line.PreviousSibling.IndexInParent + 1, 'index');
    N := Line.NextSiblingElement;
    CheckEqualsUtf8('2', N.AttributeValueUtf8('', 'no'), 'next sibling element');
    CheckEqualsUtf8('A & B', Line.ChildTextUtf8('urn:def', 'Name'), 'child text');
    CheckEqualsUtf8('', Line.ChildTextUtf8('', 'Name'), 'no-namespace lookup does not match');
    CheckEqualsUtf8('Cx<y', N.TextUtf8, 'text includes CDATA');
    N := Root.FindChild('urn:inv', 'Note');
    CheckEqualsUtf8('mixed bold text', N.TextUtf8, 'mixed content text, comments excluded');
    CheckEquals(4, N.ChildCount, 'mixed content children');
    Check(Root.FindChild('urn:inv', 'Missing') = nil, 'missing child');
    Check(Root.FindChild('urn:nowhere', 'Line') = nil, 'unknown namespace');
    Check(Root.FindChildLocal('Line') = Line, 'FindChildLocal');
    Check(Root.FindDescendant('urn:def', 'Qty') <> nil, 'FindDescendant');
    Check(Root.FindDescendant('urn:def', 'b') = N.FindChild('urn:def', 'b'), 'descendant in mixed content');
  finally
    Doc.Free;
  end;
end;

procedure TestSearchHelpers;
var
  Doc: TLandrixXmlDocument;
  L: TList;
  Root: TLandrixXmlNode;
  V: TLandrixXmlUtf8;
begin
  Doc := Load(Sample);
  L := TList.Create;
  try
    Root := Doc.Root;
    CheckEquals(2, Root.FindChildren('urn:def', 'Line', L), 'FindChildren');
    CheckEquals(2, Integer(L.Count), 'list filled');
    CheckEqualsUtf8('/inv:Invoice/Line[2]', TLandrixXmlNode(L[1]).NodePathUtf8, 'NodePath with ordinal');
    CheckEqualsUtf8('/inv:Invoice/inv:Note', Root.FindChild('urn:inv', 'Note').NodePathUtf8,
      'NodePath without ordinal');
    CheckEqualsUtf8('/inv:Invoice/inv:Note/text()', Root.FindChild('urn:inv', 'Note')[0].NodePathUtf8,
      'NodePath of text');
    CheckEqualsUtf8('/', Doc.NodePathUtf8, 'NodePath of the document');
    Check(Root.HasAttribute('', 'id'), 'HasAttribute');
    Check(not Root.HasAttribute('urn:inv', 'id'), 'HasAttribute with namespace');
    Check(Root.TryAttributeValueUtf8('', 'id', V) and (V = '7'), 'TryAttributeValue');
    Check(not Root.TryAttributeValueUtf8('', 'nope', V) and (V = ''), 'TryAttributeValue missing');
    CheckEquals(-1, Root.AttributeIndex('', 'nope'), 'AttributeIndex missing');
    CheckEqualsUtf8('', Root.AttributeValueUtf8('', 'nope'), 'missing attribute is empty');
    Check(Root[0].FindChild('', 'x') = nil, 'FindChild on text');
    CheckEquals(0, Root[0].AttributeCount, 'attributes of text');
  finally
    L.Free;
    Doc.Free;
  end;
end;

procedure TestAccessors;
var
  Doc: TLandrixXmlDocument;
begin
  Doc := Load('<r a="'#$C3#$A4'">'#$E2#$82#$AC'</r>');
  try
    CheckEqualsWide(Wide([$20AC]), Doc.Root.TextW, 'TextW');
    CheckEqualsWide(Wide([$E4]), Doc.Root.AttributeValueW('', 'a'), 'AttributeValueW');
    CheckEqualsWide(Wide([$72]), Doc.Root.NameW, 'NameW');
    CheckEqualsStr('r', Doc.Root.Name, 'native Name');
    Doc.Root.TextW := Wide([$E4, $D83D, $DE00]);
    CheckEqualsUtf8(Utf8Bytes([$C3, $A4, $F0, $9F, $98, $80]), Doc.Root.TextUtf8, 'set TextW');
    Doc.Root.Text := 'plain';
    CheckEqualsUtf8('plain', Doc.Root[0].ValueUtf8, 'set native Text');
    try
      Doc.Root.TextUtf8 := Utf8Bytes([$C3]);
      FailNotRaised('ELandrixXmlError for invalid UTF-8');
    except
      on E: Exception do
        ExpectCode(xecInvalidUnicode, E, 'invalid UTF-8 text');
    end;
  finally
    Doc.Free;
  end;
end;

{ --- whitespace and load options ---------------------------------------------- }

procedure TestWhitespaceModes;
const
  Xml = '<r>'#10 +
    '  <a> <b>x</b> </a>'#10 +
    '  <p><s>A</s> <s>B</s></p>'#10 +
    '  <m><s>A</s> <s>B</s>tail</m>'#10 +
    '  <k xml:space="preserve"> <s> </s> <d xml:space="default"> <e/> </d></k>'#10 +
    '  <v> </v>'#10 +
    '  <c><![CDATA[ ]]> <s/></c>'#10 +
    '</r>';
var
  Doc: TLandrixXmlDocument;
begin
  Doc := Load(Xml);
  try
    CheckEquals(13, Doc.Root.ChildCount, 'preserve keeps everything');
  finally
    Doc.Free;
  end;
  Doc := TLandrixXmlDocument.Create;
  try
    Doc.WhitespaceMode := xwmDropBetweenElements;
    Doc.LoadFromBuffer(PAnsiChar(Xml)^, Length(Xml));
    CheckEqualsStr('<r><a><b>T"x"</b></a><p><s>T"A"</s><s>T"B"</s></p>' +
      '<m><s>T"A"</s>T" "<s>T"B"</s>T"tail"</m>' +
      '<k xml:space="preserve">T" "<s>T" "</s>T" "<d xml:space="default"><e></e></d></k>' +
      '<v></v><c>C" "T" "<s></s></c></r>', Dump(Doc), 'dropped where no other text');
  finally
    Doc.Free;
  end;
end;

procedure TestLoadOptions;
var
  Doc: TLandrixXmlDocument;
  Xml: AnsiString;
begin
  Xml := '<!--a--><?p x?><r><!--b--><?q y?>t</r>';
  Doc := TLandrixXmlDocument.Create;
  try
    Doc.KeepComments := False;
    Doc.KeepProcessingInstructions := False;
    Doc.LoadFromBuffer(PAnsiChar(Xml)^, Length(Xml));
    CheckEqualsStr('<r>T"t"</r>', Dump(Doc), 'comments and PIs dropped');
    Doc.KeepComments := True;
    Doc.LoadFromBuffer(PAnsiChar(Xml)^, Length(Xml));
    CheckEqualsStr('!"a"<r>!"b"T"t"</r>', Dump(Doc), 'comments kept');
    Doc.MaxDepth := 2;
    Xml := '<a><b><c/></b></a>';
    try
      Doc.LoadFromBuffer(PAnsiChar(Xml)^, Length(Xml));
      FailNotRaised('ELandrixXmlError for depth');
    except
      on E: Exception do
        ExpectCode(xecLimit, E, 'MaxDepth');
    end;
    Check(Doc.Root = nil, 'failed load leaves the document empty');
    CheckEquals(0, Doc.ChildCount, 'no children after a failed load');
  finally
    Doc.Free;
  end;
end;

procedure TestLoadErrors;
var
  Doc: TLandrixXmlDocument;
  Xml: AnsiString;
begin
  Doc := Load('<old/>');
  try
    Xml := '<r>'#10'  <a></b></r>';
    try
      Doc.LoadFromBuffer(PAnsiChar(Xml)^, Length(Xml));
      FailNotRaised('ELandrixXmlError for a malformed document');
    except
      on E: Exception do
      begin
        ExpectCode(xecSyntax, E, 'malformed');
        CheckEquals(2, ELandrixXmlError(E).Line, 'error line');
      end;
    end;
    Check(Doc.Root = nil, 'old content is gone after a failed load');
  finally
    Doc.Free;
  end;
end;

{ --- building ---------------------------------------------------------------- }

procedure TestBuild;
var
  Doc: TLandrixXmlDocument;
  Root, E: TLandrixXmlNode;
begin
  Doc := TLandrixXmlDocument.Create;
  try
    Doc.AddCommentUtf8('generated');
    Root := Doc.AddElement('urn:inv', '', 'Invoice');
    Root.DeclareNamespace('cbc', 'urn:cbc');
    Root.AddElement('cbc:ID').TextUtf8 := 'R-1';
    E := Root.AddElement('cbc:Amount');
    E.SetAttributeUtf8('currencyID', 'EUR');
    E.Text := '119.00';
    Root.AddElement('urn:cac', 'cac', 'Party').AddElement('Name').AddTextUtf8('A & B');
    Root.AddElement('Plain');
    Root.AddElement('', '', 'NoNs');
    E := Root.AddElement('Mixed');
    E.AddTextUtf8('a ');
    E.AddElement('b').AddTextUtf8('bold');
    E.AddCDataUtf8('<x>');
    Root.SetAttributeNsUtf8('urn:ext', 'ext', 'flag', 'true');
    Root.SetAttributeUtf8('xml:lang', 'de');
    Root.AddProcessingInstruction('pi', 'v');
    CheckEqualsUtf8(U(Decl + '<!--generated--><Invoice xmlns="urn:inv" xmlns:cbc="urn:cbc" ' +
      'xmlns:ext="urn:ext" ext:flag="true" xml:lang="de"><cbc:ID>R-1</cbc:ID>' +
      '<cbc:Amount currencyID="EUR">119.00</cbc:Amount>' +
      '<cac:Party xmlns:cac="urn:cac"><Name>A &amp; B</Name></cac:Party><Plain/><NoNs xmlns=""/>' +
      '<Mixed>a <b>bold</b><![CDATA[<x>]]></Mixed><?pi v?></Invoice>'), Doc.SaveToUtf8, 'saved');
    CheckEqualsUtf8('urn:inv', Root.FindChildLocal('Plain').NamespaceUriUtf8,
      'unprefixed QName takes the default namespace');
    CheckEqualsUtf8('', Root.FindChildLocal('NoNs').NamespaceUriUtf8, 'explicit no namespace');
    CheckEqualsUtf8('urn:inv', Root.FindChild('urn:cac', 'Party')[0].NamespaceUriUtf8,
      'Name inside cac:Party is in the default namespace');
    Root.SetAttributeUtf8('ext:flag', 'false');
    CheckEqualsUtf8('false', Root.AttributeValueUtf8('urn:ext', 'flag'), 'SetAttribute replaces');
    CheckEquals(5, Root.AttributeCount, 'no duplicate attribute');
    Check(Root.RemoveAttribute('urn:ext', 'flag'), 'RemoveAttribute');
    CheckEquals(4, Root.AttributeCount, 'attribute removed');
  finally
    Doc.Free;
  end;
end;

procedure TestBuildErrors;
var
  Doc: TLandrixXmlDocument;
  Root: TLandrixXmlNode;

  procedure Expect(Step: Integer; Code: TLandrixXmlErrorCode; const Name: string);
  begin
    try
      case Step of
        0: Root.AddElement('x:y');
        1: Doc.AddElement('second');
        2: Doc.AddTextUtf8('text');
        3: Root.AddElement('1bad');
        4: Root.AddElement('a:b:c');
        5: Root.DeclareNamespace('xmlns', 'urn:x');
        6: Root.DeclareNamespace('p', '');
        7: Root.SetAttributeUtf8('q:a', '1');
        8: Root[0].AddElement('x');
        9: Root.ValueUtf8 := 'v';
        10: Root.AppendChild(Root);
        11: Root.AppendChild(Doc);
        12: Root.AddElement('', 'p', 'x');
        13: Root.DeclareNamespace('p', 'urn:other');
      end;
      FailNotRaised('ELandrixXmlError for ' + Name);
    except
      on E: Exception do
        ExpectCode(Code, E, Name);
    end;
  end;

begin
  Doc := TLandrixXmlDocument.Create;
  try
    Root := Doc.AddElement('r');
    Root.AddTextUtf8('t');
    Root.DeclareNamespace('p', 'urn:p');
    Expect(0, xecNamespace, 'undeclared prefix');
    Expect(1, xecInvalidOperation, 'second root');
    Expect(2, xecInvalidOperation, 'text in the document');
    Expect(3, xecInvalidArgument, 'invalid name');
    Expect(4, xecNamespace, 'two colons');
    Expect(5, xecNamespace, 'declare xmlns');
    Expect(6, xecNamespace, 'prefix to empty URI');
    Expect(7, xecNamespace, 'undeclared attribute prefix');
    Expect(8, xecInvalidOperation, 'element below text');
    Expect(9, xecInvalidOperation, 'value of an element');
    Expect(10, xecInvalidArgument, 'node below itself');
    Expect(11, xecInvalidArgument, 'document as a child');
    Expect(12, xecInvalidArgument, 'prefix without namespace');
    Expect(13, xecNamespace, 'redeclare a prefix differently');
  finally
    Doc.Free;
  end;
end;

{ --- moving and freeing ------------------------------------------------------- }

procedure TestMoveAndFree;
var
  Doc: TLandrixXmlDocument;
  Root, A, B, C: TLandrixXmlNode;
begin
  Doc := Load('<r><a/><b/><c/></r>');
  try
    Root := Doc.Root;
    A := Root[0];
    B := Root[1];
    C := Root[2];
    B.Detach;
    CheckEquals(2, Root.ChildCount, 'detached');
    CheckEquals(1, C.IndexInParent, 'indices renumbered');
    Check(B.Parent = nil, 'detached node has no parent');
    CheckEquals(-1, B.IndexInParent, 'detached node has no index');
    Root.InsertChild(0, B);
    CheckEqualsStr('<r><b></b><a></a><c></c></r>', Dump(Doc), 'inserted at the front');
    Root.AppendChild(B);
    CheckEqualsStr('<r><a></a><c></c><b></b></r>', Dump(Doc), 'moved to the end');
    CheckEquals(2, B.IndexInParent, 'index after the move');
    C.AppendChild(A);
    CheckEqualsStr('<r><c><a></a></c><b></b></r>', Dump(Doc), 'moved into a sibling');
    C.Remove;
    CheckEqualsStr('<r><b></b></r>', Dump(Doc), 'removed with its subtree');
    B.Detach;
    Root.AddElement('n');
    Root.Clear;
    CheckEquals(0, Root.ChildCount, 'Clear');
    { B stays owned by the document and is freed with it }
  finally
    Doc.Free;
  end;
end;

procedure TestDeepTree;
var
  Doc: TLandrixXmlDocument;
  N: TLandrixXmlNode;
  I: Integer;
  S: TLandrixXmlUtf8;
begin
  Doc := TLandrixXmlDocument.Create;
  try
    N := Doc.AddElement('', '', 'd');
    for I := 1 to 100000 do
      N := N.AddElement('', '', 'd');
    S := Doc.SaveToUtf8;
    CheckEquals(Length(Decl) + 100000 * 7 + 4, Length(S), 'deep tree saved without recursion');
    Check(Doc.Root.FindDescendant('', 'x') = nil, 'deep search without recursion');
  finally
    Doc.Free;
  end;
end;

{ --- saving and reloading ------------------------------------------------------ }

procedure TestRoundTrip;
var
  Doc, Doc2: TLandrixXmlDocument;
  S: TLandrixXmlUtf8;
begin
  Doc := Load(Sample);
  Doc2 := TLandrixXmlDocument.Create;
  try
    S := Doc.SaveToUtf8;
    Doc2.LoadFromUtf8(S);
    CheckEqualsStr(Dump(Doc), Dump(Doc2), 'same nodes after save and reload');
    CheckEqualsStr(DumpTokens(Sample), DumpTokens(Raw(S)), 'same tokens');
    Doc.Indent := True;
    Doc.LineBreak := xlbCRLF;
    Doc2.LoadFromUtf8(Doc.SaveToUtf8);
    CheckEqualsStr(Dump(Doc), Dump(Doc2), 'indentation keeps mixed content and text');
  finally
    Doc2.Free;
    Doc.Free;
  end;
end;

procedure TestIndentedBuild;
var
  Doc: TLandrixXmlDocument;
  Root: TLandrixXmlNode;
begin
  Doc := TLandrixXmlDocument.Create;
  try
    Doc.Indent := True;
    Doc.WriteDeclaration := False;
    Root := Doc.AddElement('GAEB');
    Root.AddElement('Award').AddElement('ID').TextUtf8 := '1';
    Root.AddElement('Text').AddElement('p').AddTextUtf8('long text');
    CheckEqualsUtf8(U('<GAEB>'#10'  <Award>'#10'    <ID>1</ID>'#10'  </Award>'#10 +
      '  <Text>'#10'    <p>long text</p>'#10'  </Text>'#10'</GAEB>'), Doc.SaveToUtf8, 'indented');
  finally
    Doc.Free;
  end;
end;

procedure TestAppendFromReader;
var
  Doc: TLandrixXmlDocument;
  Reader: TLandrixXmlReader;
  N: TLandrixXmlNode;
begin
  Doc := TLandrixXmlDocument.Create;
  Reader := TLandrixXmlReader.Create;
  try
    Doc.WriteDeclaration := False;
    Doc.AddElement('collected');
    Reader.LoadFromUtf8('<a:r xmlns:a="urn:a" xmlns="urn:d"><x>1</x><a:item k="v"><y/></a:item>' +
      '<x>2</x></a:r>');
    while Reader.Read do
      if (Reader.TokenType = xttStartElement) and (Reader.LocalNameUtf8 = 'item') then
      begin
        N := Doc.Root.AppendFromReader(Reader);
        CheckEquals(Ord(xttEndElement), Ord(Reader.TokenType), 'reader on the end tag');
        CheckEqualsUtf8('urn:a', N.NamespaceUriUtf8, 'namespace kept');
      end;
    CheckEqualsUtf8('<collected><a:item k="v" xmlns:a="urn:a" xmlns="urn:d"><y/></a:item></collected>',
      Doc.SaveToUtf8, 'missing declarations added');
    Doc.Root.Clear;
    Reader.LoadFromUtf8('<z/>');
    Reader.Read;
    Doc.Root.Remove;
    Doc.AppendFromReader(Reader);
    CheckEqualsUtf8('<z/>', Doc.SaveToUtf8, 'root element from a reader');
  finally
    Reader.Free;
    Doc.Free;
  end;
end;

procedure TestSubtreeWrite;
var
  Doc: TLandrixXmlDocument;
  W: TLandrixXmlWriter;
begin
  Doc := Load('<r xmlns="urn:d" xmlns:p="urn:p"><p:a><b/></p:a></r>');
  W := TLandrixXmlWriter.Create;
  try
    W.WriteDeclaration := False;
    Doc.Root[0].WriteTo(W);
    W.EndDocument;
    CheckEqualsUtf8('<p:a xmlns="urn:d" xmlns:p="urn:p"><b/></p:a>', W.AsUtf8,
      'a subtree repeats the declarations in scope');
  finally
    W.Free;
    Doc.Free;
  end;
end;

procedure TestLargeDocument;
var
  Doc: TLandrixXmlDocument;
  B: TLandrixXmlBuffer;
  I: Integer;
  L: TList;
begin
  B := TLandrixXmlBuffer.Create;
  Doc := TLandrixXmlDocument.Create;
  L := TList.Create;
  try
    B.AppendAscii('<GAEB xmlns="http://www.gaeb.de/GAEB_DA_XML/DA84/3.2">');
    for I := 1 to 50000 do
    begin
      B.AppendAscii('<Item RNoPart="');
      B.AppendUtf8(LandrixXmlStringToUtf8(IntToStr(I)));
      B.AppendAscii('"><Qty>1.000</Qty><Description><p><span>Text</span></p></Description></Item>');
    end;
    B.AppendAscii('</GAEB>');
    Doc.LoadFromBuffer(B.Data^, B.Size);
    CheckEquals(50000, Doc.Root.FindChildren('http://www.gaeb.de/GAEB_DA_XML/DA84/3.2', 'Item', L),
      'all items');
    CheckEqualsUtf8('50000', TLandrixXmlNode(L[49999]).AttributeValueUtf8('', 'RNoPart'), 'last item');
  finally
    L.Free;
    Doc.Free;
    B.Free;
  end;
end;

procedure TestNamespaceConsistency;
var
  Doc, Doc2: TLandrixXmlDocument;
  Root, A, Q: TLandrixXmlNode;
begin
  Doc := TLandrixXmlDocument.Create;
  Doc2 := TLandrixXmlDocument.Create;
  try
    Doc.WriteDeclaration := False;
    { no-namespace element under a default namespace }
    Root := Doc.AddElement('urn:d', '', 'r');
    Root.AddElement('', '', 'NoNs').AddElement('', '', 'inner');
    CheckEqualsUtf8('<r xmlns="urn:d"><NoNs xmlns=""><inner/></NoNs></r>', Doc.SaveToUtf8,
      'xmlns="" written');
    Doc2.LoadFromUtf8(Doc.SaveToUtf8);
    CheckEqualsStr(Dump(Doc), Dump(Doc2), 'reload after an API build');

    { moving across namespace scopes }
    Doc.LoadFromUtf8('<r xmlns:p="urn:p"><p:a/><q xmlns:p="urn:other"/><b/><z xmlns="urn:z"/></r>');
    Root := Doc.Root;
    A := Root[0];
    Q := Root[1];
    Q.AppendChild(A);
    Root.FindChildLocal('z').AppendChild(Root.FindChildLocal('b'));
    Doc2.LoadFromUtf8(Doc.SaveToUtf8);
    CheckEqualsStr(Dump(Doc), Dump(Doc2), 'moves keep the namespaces');
    CheckEqualsUtf8('urn:p', Doc2.Root[0][0].NamespaceUriUtf8, 'moved prefixed element');

    { a declaration must not rebind a prefix in use }
    Doc.LoadFromUtf8('<r xmlns:p="urn:1"><p:a p:x="1"/><c p:y="2"/></r>');
    try
      Doc.Root[0].SetAttributeNsUtf8('urn:2', 'p', 'z', 'v');
      FailNotRaised('ELandrixXmlError for rebinding the element prefix');
    except
      on E: Exception do
        ExpectCode(xecNamespace, E, 'rebinding the element prefix');
    end;
    try
      Doc.Root[1].DeclareNamespace('p', 'urn:2');
      FailNotRaised('ELandrixXmlError for rebinding an attribute prefix');
    except
      on E: Exception do
        ExpectCode(xecNamespace, E, 'rebinding an attribute prefix');
    end;
    CheckEquals(1, Doc.Root[1].AttributeCount, 'nothing added');

    { late default namespace (GAEB pattern) stays allowed }
    Doc.Clear;
    Root := Doc.AddElement('GAEB');
    Root.AddElement('Award');
    Root.SetAttributeUtf8('xmlns', 'urn:gaeb');
    Doc2.LoadFromUtf8(Doc.SaveToUtf8);
    CheckEqualsUtf8('urn:gaeb', Doc2.Root.FindChildLocal('Award').NamespaceUriUtf8,
      'late default namespace applies after reload');
  finally
    Doc2.Free;
    Doc.Free;
  end;
end;

procedure TestInsertChildChecks;
var
  Doc: TLandrixXmlDocument;
  Root, B, C: TLandrixXmlNode;
begin
  Doc := Load('<r><a/><b/></r>');
  try
    Root := Doc.Root;
    B := Root[1];
    try
      Root.InsertChild(99, B);
      FailNotRaised('ELandrixXmlError for a bad index');
    except
      on E: Exception do
        ExpectCode(xecInvalidArgument, E, 'bad index');
    end;
    Check(B.Parent = Root, 'node unchanged after a bad index');
    CheckEquals(2, Root.ChildCount, 'children unchanged');
    B.Detach;
    C := Root.AddElement('c');
    C.Detach;
    try
      Root.InsertChild(-1, B);
      FailNotRaised('ELandrixXmlError for a negative index');
    except
      on E: Exception do
        ExpectCode(xecInvalidArgument, E, 'negative index');
    end;
    B.Remove;
    Root.AppendChild(C);
    CheckEqualsStr('<r><a></a><c></c></r>', Dump(Doc), 'detached nodes removed and re-added');
    Root.AddElement('d').Detach;
    Root.AddElement('e').Detach;
    Doc.Clear;
    Check(Doc.Root = nil, 'Clear with detached nodes outstanding');
    try
      Doc.Standalone := 'maybe';
      FailNotRaised('ELandrixXmlError for Standalone');
    except
      on E: Exception do
        ExpectCode(xecInvalidArgument, E, 'Standalone value');
    end;
  finally
    Doc.Free;
  end;
end;

procedure Register;
begin
  RegisterTest('Dom.NamespaceConsistency', TestNamespaceConsistency);
  RegisterTest('Dom.InsertChildChecks', TestInsertChildChecks);
  RegisterTest('Dom.LoadAndNavigate', TestLoadAndNavigate);
  RegisterTest('Dom.SearchHelpers', TestSearchHelpers);
  RegisterTest('Dom.Accessors', TestAccessors);
  RegisterTest('Dom.WhitespaceModes', TestWhitespaceModes);
  RegisterTest('Dom.LoadOptions', TestLoadOptions);
  RegisterTest('Dom.LoadErrors', TestLoadErrors);
  RegisterTest('Dom.Build', TestBuild);
  RegisterTest('Dom.BuildErrors', TestBuildErrors);
  RegisterTest('Dom.MoveAndFree', TestMoveAndFree);
  RegisterTest('Dom.DeepTree', TestDeepTree);
  RegisterTest('Dom.RoundTrip', TestRoundTrip);
  RegisterTest('Dom.IndentedBuild', TestIndentedBuild);
  RegisterTest('Dom.AppendFromReader', TestAppendFromReader);
  RegisterTest('Dom.SubtreeWrite', TestSubtreeWrite);
  RegisterTest('Dom.LargeDocument', TestLargeDocument);
end;

end.
