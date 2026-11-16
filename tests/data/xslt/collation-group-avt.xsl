<?xml version="1.0" encoding="UTF-8"?>
<!-- the collation of xsl:for-each-group is an attribute value template -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:variable name="ns" select="'www.w3.org/2005/xpath-functions/'"/>
  <xsl:template match="/">
    <out>
      <xsl:for-each-group select="('a', 'b', 'a', 'A')" group-by="." collation="http://{$ns}collation/codepoint">
        <g key="{current-grouping-key()}" n="{count(current-group())}"/>
      </xsl:for-each-group>
      <xsl:for-each-group select="(1, 1, 2)" group-adjacent="." collation=" http://www.w3.org/2005/xpath-functions/collation/codepoint ">
        <a n="{count(current-group())}"/>
      </xsl:for-each-group>
    </out>
  </xsl:template>
</xsl:stylesheet>
