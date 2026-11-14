<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:xs="http://www.w3.org/2001/XMLSchema"
  xmlns:p="urn:v" xmlns:q="urn:v" exclude-result-prefixes="xs p q">
  <xsl:variable name="a" as="xs:integer" select="$b + 1"/>
  <xsl:variable name="b" select="41"/>
  <xsl:variable name="empty" as="xs:string*"/>
  <xsl:variable name="unused" as="xs:integer" select="xs:integer('bad')"/>
  <xsl:variable name="p:v" select="'by-uri'"/>
  <xsl:template match="/"><out a="{$a}" e="{count($empty)}" v="{$q:v}"/></xsl:template>
</xsl:stylesheet>
