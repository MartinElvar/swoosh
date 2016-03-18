defmodule Swoosh.Adapters.SMTP do
  alias Swoosh.Email

  @behaviour Swoosh.Adapter

  def deliver(%Swoosh.Email{} = email, config) do
    {_from_name, from_address} = email.from
    recipients = recipients(email)
    {type, subtype, headers, parts} = prepare_message(email)
    body = :mimemail.encode({type, subtype, headers, [], parts})
    case :gen_smtp_client.send_blocking({from_address, recipients, body}, config) do
      receipt when is_binary(receipt) -> {:ok, receipt}
      {:error, type, message} -> {:error, {type, message}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp recipients(email) do
    Enum.concat([email.to, email.cc, email.bcc])
    |> Enum.map(fn {_name, address} -> address end)
    |> Enum.uniq
  end

  @doc false
  def prepare_message(email) do
    prepare_headers(email)
    |> prepare_parts(email)
  end

  defp prepare_headers(%Email{} = email) do
    []
    |> prepare_mime_version
    |> prepare_subject(email)
    |> prepare_cc(email)
    |> prepare_to(email)
    |> prepare_from(email)
  end

  defp prepare_subject(_headers, %Email{subject: nil}), do: raise ArgumentError, message: "`subject` can't be nil"
  defp prepare_subject(headers, %Email{subject: subject}), do: [{"Subject", subject} | headers]

  defp prepare_from(_headers, %Email{from: nil}), do: raise ArgumentError, message: "`from` can't be nil"
  defp prepare_from(_headers, %Email{from: {_name, nil}}), do: raise ArgumentError, message: "`from` address can't be nil"
  defp prepare_from(headers, %Email{from: from}), do: [{"From", prepare_recipient(from)} | headers]

  defp prepare_to(_headers, %Email{to: []}), do: raise ArgumentError, message: "`to` can't be empty"
  defp prepare_to(headers, %Email{to: to}), do: [{"To", "#{prepare_recipients(to)}"} | headers]

  defp prepare_cc(headers, %Email{cc: []}), do: headers
  defp prepare_cc(headers, %Email{cc: cc}), do: [{"Cc", "#{prepare_recipients(cc)}"} | headers]

  defp prepare_mime_version(headers), do: [{"Mime-Version", "1.0"} | headers]

  defp prepare_recipients(recipients) do
    recipients
    |> Enum.map(&prepare_recipient(&1))
    |> Enum.join(", ")
  end

  defp prepare_recipient({nil, address}), do: address
  defp prepare_recipient({"", address}), do: address
  defp prepare_recipient({name, address}), do: "#{name} <#{address}>"

  defp prepare_parts(headers, %Email{html_body: nil, text_body: text_body}) do
    headers = [{"Content-Type", "text/plain; charset=\"utf-8\""} | headers]
    {"text", "plain", headers, text_body}
  end
  defp prepare_parts(headers, %Email{html_body: html_body, text_body: nil}) do
    headers = [{"Content-Type", "text/html; charset=\"utf-8\""} | headers]
    {"text", "html", headers, html_body}
  end
  defp prepare_parts(headers, %Email{html_body: html_body, text_body: text_body}) do
    parts = [prepare_part(:plain, text_body), prepare_part(:html, html_body)]
    {"multipart", "alternative", headers, parts}
  end

  defp prepare_part(subtype, content) do
    subtype_string = to_string(subtype)
    {"text",
     subtype_string,
     [{"Content-Type", "text/#{subtype_string}; charset=\"utf-8\""},
      {"Content-Transfer-Encoding", "quoted-printable"}],
     [{"content-type-params", [{"charset", "utf-8"}]},
      {"disposition", "inline"},
      {"disposition-params",[]}],
     content}
  end
end