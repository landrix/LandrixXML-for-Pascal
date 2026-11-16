<?xml version="1.0" encoding="UTF-8"?>
<!-- raw text in script: a character US-ASCII lacks is a character
     reference (written as is, without disable-output-escaping, it is
     SERE0008) -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="html" encoding="US-ASCII"/>
  <xsl:template match="/">
    <html><head><script><xsl:value-of select="'if (a &lt; b) x = &quot;&#233;&quot;;'" disable-output-escaping="yes"/></script></head></html>
  </xsl:template>
</xsl:stylesheet>
