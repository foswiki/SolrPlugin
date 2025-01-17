// by Elvis Rocha
// see https://issues.apache.org/jira/browse/SOLR-6468
package filters;

import java.io.IOException;
import java.util.Map;

import org.apache.lucene.analysis.TokenFilter;
import org.apache.lucene.analysis.TokenStream;
import org.apache.lucene.analysis.tokenattributes.PositionIncrementAttribute;
import org.apache.lucene.analysis.util.TokenFilterFactory;

public class RemoveTokenGapsFilterFactory extends TokenFilterFactory {

	public RemoveTokenGapsFilterFactory(Map<String, String> args) {
		super(args);
	}

	@Override
	public TokenStream create(TokenStream input) {
		RemoveTokenGapsFilter filter = new RemoveTokenGapsFilter(input);
		return filter;
	}

}

final class RemoveTokenGapsFilter extends TokenFilter {

	private final PositionIncrementAttribute posIncrAtt = addAttribute(PositionIncrementAttribute.class);

	public RemoveTokenGapsFilter(TokenStream input) {
		super(input);
	}

	@Override
	public final boolean incrementToken() throws IOException {
		while (input.incrementToken()) {
			posIncrAtt.setPositionIncrement(1);
			return true;
		}
		return false;
	}
}
