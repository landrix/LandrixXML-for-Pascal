<?xml version="1.0" encoding="UTF-8"?>
<!-- forwards compatible: an unknown instruction without xsl:fallback is
     a static error in Saxon (XTSE0010) -->
<xsl:stylesheet version="4.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/"><out><xsl:if test="false()"><xsl:newthing/></xsl:if></out></xsl:template>
</xsl:stylesheet>
