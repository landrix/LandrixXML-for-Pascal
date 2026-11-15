<?xml version="1.0" encoding="UTF-8"?>
<!-- xsl:copy-of at the top of a typed sequence, as Saxon gives it: an
     element keeps its base URI with the xml:base of its ancestors; a
     copied xml:base is resolved against the static base of the
     xsl:copy-of (and applies once more), in a variable and in a
     function result. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:f="urn:f" xml:base="http://s/a/">
  <xsl:function name="f:cp" as="element()*" xml:base="http://s/fc/"><xsl:param name="r"/><xsl:copy-of select="$r/i, $r/k"/></xsl:function>
  <xsl:template match="/">
    <out>
      <xsl:variable name="v" as="element()*" xml:base="http://variable/"><xsl:copy-of select="r/k" xml:base="http://copier/"/><xsl:copy-of select="r/i"/></xsl:variable>
      <a><xsl:value-of select="for $e in $v return base-uri($e)"/></a>
      <b><xsl:value-of select="for $e in f:cp(r) return base-uri($e)"/></b>
    </out>
  </xsl:template>
</xsl:stylesheet>
