<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- white space of the stylesheet is stripped before elements with use-when="false()" are left out -->
<xsl:template match="/"><r><a>A<x xsl:use-when="false()"/> </a><b> <x xsl:use-when="false()"/> </b><c> <!--k--> <x xsl:use-when="false()"/>B</c><d>
  <xsl:if test="1" use-when="false()"/>
  <xsl:value-of select="'v'"/></d><e xml:space="preserve"> <x xsl:use-when="false()"/> </e><f><xsl:text> <!--k--> </xsl:text></f><g><b xsl:use-when="ends-with(resolve-uri('x.xml'), '/x.xml')">resolved</b></g></r></xsl:template>
</xsl:stylesheet>
