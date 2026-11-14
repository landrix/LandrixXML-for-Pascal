<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- xsl:analyze-string: matches and the substrings between, position() and last(), regex-group(), flags, AVTs, nesting, no match -->
<xsl:template match="/">
<r>
<a><xsl:analyze-string select="'ab12cd345e'" regex="([0-9])([0-9]*)">
  <xsl:matching-substring><m p="{position()}" l="{last()}" g0="{regex-group(0)}" g1="{regex-group(1)}" g2="{regex-group(2)}" g3="{regex-group(3)}" dot="{.}"/></xsl:matching-substring>
  <xsl:non-matching-substring><n p="{position()}" g1="{regex-group(1)}"><xsl:value-of select="."/></n></xsl:non-matching-substring>
</xsl:analyze-string></a>
<b><xsl:analyze-string select="'Hello World'" regex="{'o'}" flags="{'i'}"><xsl:matching-substring>[<xsl:value-of select="."/>]</xsl:matching-substring></xsl:analyze-string></b>
<c><xsl:analyze-string select="'aXbXc'" regex="x" flags="i"><xsl:non-matching-substring><xsl:value-of select="."/></xsl:non-matching-substring></xsl:analyze-string></c>
<d><xsl:analyze-string select="'a1-b22'" regex="([a-z])([0-9]+)">
  <xsl:matching-substring><xsl:analyze-string select="regex-group(2)" regex="2"><xsl:matching-substring>(<xsl:value-of select="regex-group(0)"/>)</xsl:matching-substring><xsl:non-matching-substring>{<xsl:value-of select="."/>}</xsl:non-matching-substring></xsl:analyze-string>/<xsl:value-of select="regex-group(1)"/></xsl:matching-substring>
  <xsl:non-matching-substring>|</xsl:non-matching-substring>
</xsl:analyze-string></d>
<e><xsl:analyze-string select="'abc'" regex="x"><xsl:matching-substring>M</xsl:matching-substring><xsl:non-matching-substring><xsl:value-of select="concat(., position(), last())"/></xsl:non-matching-substring></xsl:analyze-string></e>
<f><xsl:analyze-string select="()" regex="x"><xsl:non-matching-substring>N</xsl:non-matching-substring></xsl:analyze-string>-<xsl:value-of select="regex-group(1)"/>-</f>
<g><xsl:analyze-string select="'a(b)c'" regex="(b)?\(|\)"><xsl:matching-substring><x g1="{regex-group(1)}"/></xsl:matching-substring></xsl:analyze-string></g>
<h><xsl:analyze-string select="'line1&#10;line2'" regex="^line" flags="m"><xsl:matching-substring>*</xsl:matching-substring><xsl:non-matching-substring><xsl:value-of select="."/></xsl:non-matching-substring></xsl:analyze-string></h>
<j><xsl:analyze-string select="'x1y'" regex="([0-9])"><xsl:matching-substring>[<xsl:value-of select="f:g(1)"/>|<xsl:value-of select="regex-group(1)"/>]<xsl:for-each select="1"><xsl:value-of select="regex-group(1)"/></xsl:for-each></xsl:matching-substring></xsl:analyze-string></j>
<k><xsl:analyze-string select="'x1y'" regex="([0-9])"><xsl:matching-substring>[<xsl:call-template name="t"/>|<xsl:apply-templates select="$doc/a"/>|<xsl:value-of select="$g"/>|<xsl:value-of select="$gb"/>]</xsl:matching-substring></xsl:analyze-string></k>
<l><xsl:analyze-string select="'x1y'" regex="([0-9])"><xsl:matching-substring><xsl:value-of select="count(key('rk', '', $doc))"/></xsl:matching-substring></xsl:analyze-string></l>
<i><xsl:value-of select="element-available('xsl:analyze-string'), function-available('regex-group')"/></i>
</r>
</xsl:template>
<xsl:function name="f:g"><xsl:param name="n"/><xsl:sequence select="concat('(', regex-group($n), ')')"/></xsl:function>
<!-- templates keep the captured substrings, global variables do not see them (as Saxon) -->
<xsl:key name="rk" match="a" use="regex-group(1)"/>
<xsl:variable name="g" select="regex-group(1)"/>
<xsl:variable name="gb"><xsl:value-of select="regex-group(1)"/></xsl:variable>
<xsl:variable name="doc"><a/></xsl:variable>
<xsl:template name="t">c<xsl:value-of select="regex-group(1)"/></xsl:template>
<xsl:template match="a">a<xsl:value-of select="regex-group(1)"/></xsl:template>
</xsl:stylesheet>
