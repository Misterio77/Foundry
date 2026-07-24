package rs.m7.runelitemcp.protocol;

public final class DispatchResult
{
	private final int status;
	private final String body;

	private DispatchResult(int status, String body)
	{
		this.status = status;
		this.body = body;
	}

	public static DispatchResult json(String body)
	{
		return new DispatchResult(200, body);
	}

	public static DispatchResult accepted()
	{
		return new DispatchResult(202, null);
	}

	public int getStatus()
	{
		return status;
	}

	public String getBody()
	{
		return body;
	}
}
