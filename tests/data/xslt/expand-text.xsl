<?xml version="1.0" encoding="UTF-8"?>
<!-- expand-text: text value templates in sequence constructors and
     xsl:text (empty braces are the empty sequence; [xsl:]expand-text of the
     nearest ancestor decides; true, 1, false and 0 as in Saxon) -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" expand-text="yes"
    xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
  <xsl:function name="f:g"><xsl:param name="x"/><xsl:sequence select="$x * 2"/></xsl:function>
  <xsl:template match="/">
    <out>
      <a>x{1+1}y{{z}}{()}w{(1,2,3)}</a>
      <b>{ }</b>
      <c>{}</c>
      <d xsl:expand-text="no">{1}</d>
      <e><xsl:text>t{2*3}</xsl:text><xsl:text disable-output-escaping="yes">{'&lt;r/&gt;'}</xsl:text></e>
      <f>  {1}  </f>
      <g>{1}<!-- c -->{2}</g>
      <h><xsl:value-of select="1"/>{2}<xsl:sequence select="3"/></h>
      <i expand-text="no">{1}</i>
      <xsl:for-each select="1" expand-text="0">{1}</xsl:for-each>
      <xsl:for-each select="1" expand-text=" true ">[{.}]</xsl:for-each>
      <j>{'a'}{'b'}</j>
      <l>{f:g(7)}{xs:integer('3')}{(: only a comment :)}<xsl:text>[{(:c:)}]</xsl:text></l>
      <m xmlns:z="urn:f">{z:g(1)}</m>
      <k>
        {1}
      </k>
    </out>
  </xsl:template>
</xsl:stylesheet>
