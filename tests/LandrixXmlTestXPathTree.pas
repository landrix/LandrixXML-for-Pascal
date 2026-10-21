{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Tests for the XPath tree: node order, attributes, merged text, names,
  string values and SchXslt locations, built from the reader and from the
  DOM. }

unit LandrixXmlTestXPathTree;

{$I LandrixXml.inc}

interface

procedure Register;

implementation

uses
  SysUtils,
  LandrixXmlBase,
  LandrixXmlDom,
  LandrixXmlXPathTree,
  LandrixXmlTestFramework;

const
  Sample =
    '<?xml version="1.0"?>' + #10 +
    '<!-- before -->' + #10 +
    '<r:Inv xmlns:r="urn:r" xmlns="urn:d" id="7" r:x="y">' + #10 +
    '  <a>one<![CDATA[ two]]></a>' + #10 +
    '  <a/>' + #10 +
    '  <b p="q"><!-- c --><?pi data?>tail</b>' + #10 +
    '  <a>three</a>' + #10 +
    '</r:Inv>';

const
  { every node except the document in document order, as Saxon lists
    //node() | //@* with SchXslt's location function }
  SaxonLocations: array[0..18] of string = (
    '/comment()[1]',
    '/Q{urn:r}Inv[1]',
    '/Q{urn:r}Inv[1]/@Q{}id',
    '/Q{urn:r}Inv[1]/@Q{urn:r}x',
    '/Q{urn:r}Inv[1]/text()[1]',
    '/Q{urn:r}Inv[1]/Q{urn:d}a[1]',
    '/Q{urn:r}Inv[1]/Q{urn:d}a[1]/text()[1]',
    '/Q{urn:r}Inv[1]/text()[2]',
    '/Q{urn:r}Inv[1]/Q{urn:d}a[2]',
    '/Q{urn:r}Inv[1]/text()[3]',
    '/Q{urn:r}Inv[1]/Q{urn:d}b[1]',
    '/Q{urn:r}Inv[1]/Q{urn:d}b[1]/@Q{}p',
    '/Q{urn:r}Inv[1]/Q{urn:d}b[1]/comment()[1]',
    '/Q{urn:r}Inv[1]/Q{urn:d}b[1]/processing-instruction("pi")[1]',
    '/Q{urn:r}Inv[1]/Q{urn:d}b[1]/text()[1]',
    '/Q{urn:r}Inv[1]/text()[4]',
    '/Q{urn:r}Inv[1]/Q{urn:d}a[3]',
    '/Q{urn:r}Inv[1]/Q{urn:d}a[3]/text()[1]',
    '/Q{urn:r}Inv[1]/text()[5]');

const
  { a document with the cases the data model has rules for, and the
    locations Saxon gives its nodes (same listing as above) }
  Tricky =
    '<?pi0 top?><!--c0--><r xmlns:a="urn:x" xmlns:b="urn:x" a:k="1" b:j="2" xml:lang="de">' +
    't1<!--c1-->t2<?p?>t3<![CDATA[c]]><![CDATA[d]]><a:e/><b:e/><e/>&amp;<![CDATA[]]>' +
    '<f><![CDATA[]]></f><g><!-- only --></g></r><!--c2--><?pi0?>';
  TrickyLocations: array[0..19] of string = (
    '/processing-instruction("pi0")[1]',
    '/comment()[1]',
    '/Q{}r[1]',
    '/Q{}r[1]/@Q{urn:x}k',
    '/Q{}r[1]/@Q{urn:x}j',
    '/Q{}r[1]/@Q{http://www.w3.org/XML/1998/namespace}lang',
    '/Q{}r[1]/text()[1]',
    '/Q{}r[1]/comment()[1]',
    '/Q{}r[1]/text()[2]',
    '/Q{}r[1]/processing-instruction("p")[1]',
    '/Q{}r[1]/text()[3]',
    '/Q{}r[1]/Q{urn:x}e[1]',
    '/Q{}r[1]/Q{urn:x}e[2]',
    '/Q{}r[1]/Q{}e[1]',
    '/Q{}r[1]/text()[4]',
    '/Q{}r[1]/Q{}f[1]',
    '/Q{}r[1]/Q{}g[1]',
    '/Q{}r[1]/Q{}g[1]/comment()[1]',
    '/comment()[2]',
    '/processing-instruction("pi0")[2]');

function U(const S: string): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(S);
end;

{ Finds the n-th node (1-based) of a kind with a local name ('' = any). }
function NodeOf(T: TLandrixXmlXPathTree; Kind: TLandrixXmlXPathNodeKind; const LocalName: string;
  N: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to T.Count - 1 do
    if (T.Kind[I] = Kind) and ((LocalName = '') or (T.LocalNameUtf8(I) = U(LocalName))) then
    begin
      Dec(N);
      if N = 0 then
      begin
        Result := I;
        Exit;
      end;
    end;
  Result := -1;
end;

procedure CheckTree(T: TLandrixXmlXPathTree; const Mode: string);
var
  Root, A1, A2, B, Attr, I, Text: Integer;
begin
  CheckEquals(Ord(xnkDocument), Ord(T.Kind[0]), Mode + ': document node');
  Root := T.DocumentElement;
  Check(Root > 0, Mode + ': root element');
  CheckEqualsUtf8(U('Inv'), T.LocalNameUtf8(Root), Mode + ': root local name');
  CheckEqualsUtf8(U('r:Inv'), T.NameUtf8(Root), Mode + ': root name');
  CheckEqualsUtf8(U('urn:r'), T.NamespaceUriUtf8(Root), Mode + ': root namespace');
  CheckEquals(0, T.Parent[Root], Mode + ': root parent');
  { the comment before the root is a child of the document }
  CheckEquals(Ord(xnkComment), Ord(T.Kind[T.FirstChild(0)]), Mode + ': comment first');
  { two attributes right after the element, no namespace declarations }
  CheckEquals(2, T.AttributeCount[Root], Mode + ': attribute count');
  Attr := Root + 1;
  CheckEquals(Ord(xnkAttribute), Ord(T.Kind[Attr]), Mode + ': attribute kind');
  CheckEqualsUtf8(U('id'), T.LocalNameUtf8(Attr), Mode + ': attribute name');
  CheckEqualsUtf8(U(''), T.NamespaceUriUtf8(Attr), Mode + ': attribute without namespace');
  CheckEqualsUtf8(U('7'), T.ValueUtf8(Attr), Mode + ': attribute value');
  CheckEqualsUtf8(U('r:x'), T.NameUtf8(Attr + 1), Mode + ': prefixed attribute');
  CheckEquals(Root, T.Parent[Attr], Mode + ': attribute parent');
  CheckEquals(-1, T.NextSibling[Attr], Mode + ': attribute has no sibling');
  { white space is kept: the first child is the text before <a> }
  I := T.FirstChild(Root);
  CheckEquals(Ord(xnkText), Ord(T.Kind[I]), Mode + ': white space kept');
  { text and CDATA merged }
  A1 := NodeOf(T, xnkElement, 'a', 1);
  Text := T.FirstChild(A1);
  CheckEqualsUtf8(U('one two'), T.ValueUtf8(Text), Mode + ': text and CDATA merged');
  CheckEquals(-1, T.NextSibling[Text], Mode + ': one text node');
  CheckEqualsUtf8(U('urn:d'), T.NamespaceUriUtf8(A1), Mode + ': default namespace');
  A2 := NodeOf(T, xnkElement, 'a', 2);
  CheckEquals(-1, T.FirstChild(A2), Mode + ': empty element');
  CheckEquals(A2, T.SubtreeEnd[A2], Mode + ': empty subtree');
  CheckEquals(T.ExpandedName[A1], T.ExpandedName[A2], Mode + ': same expanded name');
  CheckEquals(T.ExpandedName[A1], T.FindExpandedName(U('urn:d'), U('a')), Mode + ': find expanded name');
  CheckEquals(-1, T.FindExpandedName(U(''), U('a')), Mode + ': unknown expanded name');
  B := NodeOf(T, xnkElement, 'b', 1);
  CheckEqualsUtf8(U('tail'), T.StringValueUtf8(B), Mode + ': string value skips comment and PI');
  CheckEqualsUtf8(U('data'), T.ValueUtf8(NodeOf(T, xnkProcessingInstruction, '', 1)), Mode + ': PI value');
  CheckEqualsUtf8(U('pi'), T.LocalNameUtf8(NodeOf(T, xnkProcessingInstruction, '', 1)), Mode + ': PI target');
  CheckEqualsUtf8(U(#10'  one two'#10'  '#10'  tail'#10'  three'#10), T.StringValueUtf8(Root),
    Mode + ': string value of the root');
  CheckEquals(T.Count - 1, T.SubtreeEnd[0], Mode + ': document subtree');
  { order: every child after its parent, inside its subtree }
  for I := 1 to T.Count - 1 do
  begin
    Check(T.Parent[I] < I, Mode + ': parent before child');
    Check(T.SubtreeEnd[T.Parent[I]] >= T.SubtreeEnd[I], Mode + ': subtree nested');
  end;
  { SchXslt locations }
  CheckEqualsUtf8(U('/Q{urn:r}Inv[1]'), T.LocationPathUtf8(Root), Mode + ': root location');
  CheckEqualsUtf8(U('/Q{urn:r}Inv[1]/@Q{}id'), T.LocationPathUtf8(Attr), Mode + ': attribute location');
  CheckEqualsUtf8(U('/Q{urn:r}Inv[1]/Q{urn:d}a[2]'), T.LocationPathUtf8(A2), Mode + ': second a');
  CheckEqualsUtf8(U('/Q{urn:r}Inv[1]/Q{urn:d}a[3]'), T.LocationPathUtf8(NodeOf(T, xnkElement, 'a', 3)),
    Mode + ': third a, after b');
  CheckEqualsUtf8(U('/Q{urn:r}Inv[1]/Q{urn:d}b[1]/text()[1]'), T.LocationPathUtf8(T.SubtreeEnd[B]),
    Mode + ': text location');
  CheckEqualsUtf8(U('/Q{urn:r}Inv[1]/Q{urn:d}b[1]/comment()[1]'), T.LocationPathUtf8(T.FirstChild(B)),
    Mode + ': comment location');
  CheckEqualsUtf8(U('/Q{urn:r}Inv[1]/Q{urn:d}b[1]/processing-instruction("pi")[1]'),
    T.LocationPathUtf8(NodeOf(T, xnkProcessingInstruction, '', 1)), Mode + ': PI location');
  CheckEqualsUtf8(U('/'), T.LocationPathUtf8(0), Mode + ': document location');
  CheckEquals(Length(SaxonLocations) + 1, T.Count, Mode + ': node count as Saxon');
  for I := 1 to T.Count - 1 do
    CheckEqualsUtf8(U(SaxonLocations[I - 1]), T.LocationPathUtf8(I), Mode + ': location of node ' + IntToStr(I));
end;

procedure TestFromReader;
var
  T: TLandrixXmlXPathTree;
begin
  T := TLandrixXmlXPathTree.Create;
  try
    T.LoadFromUtf8(U(Sample));
    CheckTree(T, 'reader');
    CheckEquals(3, T.Line[T.DocumentElement], 'line of the root');
    Check(T.DomNode[T.DocumentElement] = nil, 'no DOM node');
  finally
    T.Free;
  end;
end;

procedure TestFromDocument;
var
  T: TLandrixXmlXPathTree;
  Doc: TLandrixXmlDocument;
  Root, Attr: Integer;
begin
  Doc := TLandrixXmlDocument.Create;
  T := TLandrixXmlXPathTree.Create;
  try
    Doc.LoadFromUtf8(U(Sample));
    T.LoadFromDocument(Doc);
    CheckTree(T, 'DOM');
    Root := T.DocumentElement;
    Check(T.DomNode[Root] = Doc.Root, 'DOM node of the root');
    Attr := Root + 2;
    Check(T.DomNode[Attr] = Doc.Root, 'attribute: its element');
    CheckEqualsUtf8(U('r:x'), Doc.Root.AttributeNameUtf8(T.DomAttributeIndex[Attr]), 'attribute index');
  finally
    T.Free;
    Doc.Free;
  end;
end;

procedure TestEmptyAndReload;
var
  T: TLandrixXmlXPathTree;
begin
  T := TLandrixXmlXPathTree.Create;
  try
    T.LoadFromUtf8(U('<x/>'));
    CheckEquals(2, T.Count, 'document and element');
    CheckEqualsUtf8(U(''), T.StringValueUtf8(0), 'empty string value');
    T.LoadFromUtf8(U('<y a="1"><z/></y>'));
    CheckEquals(4, T.Count, 'reloaded');
    CheckEquals(-1, T.FindExpandedName(U(''), U('x')), 'old names gone');
    CheckEqualsUtf8(U('/Q{}y[1]/Q{}z[1]'), T.LocationPathUtf8(3), 'location without namespace');
  finally
    T.Free;
  end;
end;

{ The data model rules: text split by comments and PIs, CDATA merged,
  empty CDATA no node, &amp; part of the text, prefixes for one URI,
  document-level comments and PIs, xml:lang. }
procedure TestTricky;
var
  T: TLandrixXmlXPathTree;
  Doc: TLandrixXmlDocument;
  I, Pass: Integer;
begin
  T := TLandrixXmlXPathTree.Create;
  Doc := TLandrixXmlDocument.Create;
  try
    for Pass := 1 to 2 do
    begin
      if Pass = 1 then
        T.LoadFromUtf8(U(Tricky))
      else
      begin
        Doc.LoadFromUtf8(U(Tricky));
        T.LoadFromDocument(Doc);
      end;
      CheckEquals(Length(TrickyLocations) + 1, T.Count, 'node count, pass ' + IntToStr(Pass));
      for I := 1 to T.Count - 1 do
        CheckEqualsUtf8(U(TrickyLocations[I - 1]), T.LocationPathUtf8(I),
          'location of node ' + IntToStr(I) + ', pass ' + IntToStr(Pass));
      CheckEqualsUtf8(U('t1t2t3cd&'), T.StringValueUtf8(T.DocumentElement), 'string value, pass ' + IntToStr(Pass));
      CheckEquals(T.ExpandedName[12], T.ExpandedName[13], 'a:e and b:e share the expanded name');
      Check(T.ExpandedName[13] <> T.ExpandedName[14], 'e without namespace differs');
      CheckEqualsUtf8(U('b:e'), T.NameUtf8(13), 'the prefix as written');
    end;
  finally
    Doc.Free;
    T.Free;
  end;
end;

{ Many names: the name tables grow. }
procedure TestManyNames;
var
  T: TLandrixXmlXPathTree;
  S: string;
  I, N: Integer;
begin
  S := '<r>';
  for I := 0 to 299 do
    S := S + '<p' + IntToStr(I mod 7) + ':e' + IntToStr(I) + ' xmlns:p' + IntToStr(I mod 7) + '="urn:' +
      IntToStr(I mod 13) + '" a' + IntToStr(I) + '="1"/>';
  S := S + '</r>';
  T := TLandrixXmlXPathTree.Create;
  try
    T.LoadFromUtf8(U(S));
    N := 0;
    for I := 0 to T.Count - 1 do
      if T.Kind[I] in [xnkElement, xnkAttribute] then
      begin
        Inc(N);
        CheckEquals(T.ExpandedName[I], T.FindExpandedName(T.NamespaceUriUtf8(I), T.LocalNameUtf8(I)),
          'expanded name of node ' + IntToStr(I));
      end;
    CheckEquals(601, N, 'elements and attributes');
    CheckEquals(-1, T.FindExpandedName(U('urn:99'), U('e1')), 'wrong namespace');
    CheckEqualsUtf8(U('/Q{}r[1]/Q{urn:5}e5[1]/@Q{}a5'), T.LocationPathUtf8(T.FirstChild(T.DocumentElement) + 11),
      'location after growth');
  finally
    T.Free;
  end;
end;

{ A malformed document leaves an empty tree. }
procedure TestFailedLoad;
var
  T: TLandrixXmlXPathTree;
begin
  T := TLandrixXmlXPathTree.Create;
  try
    CheckEquals(1, T.Count, 'the document node before any load');
    CheckEquals(-1, T.DocumentElement, 'no root before any load');
    CheckEqualsUtf8(U(''), T.StringValueUtf8(0), 'empty string value before any load');
    T.LoadFromUtf8(U('<a><b/></a>'));
    try
      T.LoadFromUtf8(U('<a><b></a>'));
      FailNotRaised('malformed XML');
    except
      on E: ELandrixXmlError do
        Check(E.Code <> xecNone, 'error code');
    end;
    CheckEquals(1, T.Count, 'empty after the failed load');
    CheckEquals(-1, T.DocumentElement, 'no root after the failed load');
  finally
    T.Free;
  end;
end;

procedure Register;
begin
  RegisterTest('XPathTree.FromReader', TestFromReader);
  RegisterTest('XPathTree.FromDocument', TestFromDocument);
  RegisterTest('XPathTree.EmptyAndReload', TestEmptyAndReload);
  RegisterTest('XPathTree.Tricky', TestTricky);
  RegisterTest('XPathTree.ManyNames', TestManyNames);
  RegisterTest('XPathTree.FailedLoad', TestFailedLoad);
end;

end.
