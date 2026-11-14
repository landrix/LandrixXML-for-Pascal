<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="xml" omit-xml-declaration="yes"/>
  <xsl:template match="/">
    <out>
      <xsl:for-each select="1 to 6">
        <xsl:choose>
          <xsl:when test=". mod 3 = 0">fizz</xsl:when>
          <xsl:when test=". = 4">four</xsl:when>
          <xsl:otherwise><xsl:value-of select="."/></xsl:otherwise>
        </xsl:choose>
        <xsl:if test="position() != last()">,</xsl:if>
      </xsl:for-each>
      <xsl:message>a message</xsl:message>
    </out>
  </xsl:template>
</xsl:stylesheet>
