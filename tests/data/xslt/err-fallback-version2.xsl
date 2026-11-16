<?xml version="1.0" encoding="UTF-8"?>
<!-- version 2.0: an unknown instruction is an error even with
     xsl:fallback (as Saxon) -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/"><out><xsl:newthing><xsl:fallback>x</xsl:fallback></xsl:newthing></out></xsl:template>
</xsl:stylesheet>
