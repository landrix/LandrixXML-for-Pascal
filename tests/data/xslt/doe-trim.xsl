<?xml version="1.0" encoding="UTF-8"?>
<!-- disable-output-escaping allows white space around yes, and (as Saxon) true, 1, false and 0 -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/"><out><xsl:value-of select="'&lt;'" disable-output-escaping=" yes "/><xsl:text disable-output-escaping=" no ">&lt;</xsl:text><xsl:text disable-output-escaping="true">&lt;</xsl:text><xsl:text disable-output-escaping="1">&lt;</xsl:text><xsl:text disable-output-escaping="false">&lt;</xsl:text><xsl:text disable-output-escaping="0">&lt;</xsl:text></out></xsl:template>
</xsl:stylesheet>
