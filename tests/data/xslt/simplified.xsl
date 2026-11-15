<?xml version="1.0" encoding="UTF-8"?>
<!-- A simplified stylesheet: the literal result element with xsl:version
     is the body of a template rule for "/"; xsl:exclude-result-prefixes,
     attribute value templates and instructions in it; it imports a
     simplified module (a rule for "/" of lower precedence, used by
     xsl:apply-imports only through an inner element). -->
<out xsl:version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:p="urn:p" xsl:exclude-result-prefixes="p" count="{count(//item)}" literal="1">
  <xsl:for-each select="doc/item">
    <item n="{position()}"><xsl:value-of select="."/></item>
  </xsl:for-each>
  <p:kept/>
</out>
