<?xml version="1.0" encoding="UTF-8"?>
<!-- collation URIs are resolved against the static base URI; a URI
     that only starts like a known collation is not one -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xml:base="http://www.w3.org/2005/xpath-functions/collation/"
    default-collation="http://saxon.sf.net/collationX codepoint">
  <xsl:key name="k" match="*" use="name()" collation="codepoint"/>
  <xsl:template match="/">
    <out>
      <xsl:perform-sort select="('b', 'a')">
        <xsl:sort select="." collation="{'codepoint'}"/>
      </xsl:perform-sort>
      <xsl:for-each-group select="('a', 'a')" group-by="." collation="./codepoint">
        <g n="{count(current-group())}"/>
      </xsl:for-each-group>
    </out>
  </xsl:template>
</xsl:stylesheet>
