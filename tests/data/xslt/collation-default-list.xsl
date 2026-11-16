<?xml version="1.0" encoding="UTF-8"?>
<!-- default-collation: the first URI recognized as a collation counts,
     unknown ones before it are skipped -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    default-collation="http://unknown.example/a
      http://www.w3.org/2005/xpath-functions/collation/codepoint http://unknown.example/b">
  <xsl:template match="/">
    <out xsl:default-collation="urn:x http://www.w3.org/2005/xpath-functions/collation/codepoint"><xsl:value-of select="default-collation(), compare('a', 'B')"/></out>
  </xsl:template>
</xsl:stylesheet>
