# frozen_string_literal: true

require "mail"

# Decides whether a message should be printed or skipped, and why.
# Returns [:print] or [:skip, reason_string]. Cheap header checks first,
# body-length checks last.
module EmailFilter
  def self.decide(mail)
    # return [:skip, "list mail (List-Unsubscribe)"] if mail.header["List-Unsubscribe"]

    auto = mail.header["Auto-Submitted"]&.to_s
    return [:skip, "auto-submitted: #{auto}"] if auto && auto != "no"

    # Feedback-ID is the industry-standard header for transactional /
    # notification mail (Google, GitHub, Stripe, etc.). Real customers
    # writing from a personal mailbox will never have it.
    return [:skip, "transactional (Feedback-ID present)"] if mail.header["Feedback-ID"]

    from = Array(mail.from).first.to_s
    return [:skip, "no-reply sender: #{from}"] if from.match?(/\A(?:no-?reply|do-?not-?reply)@/i)

    body = plain_body(mail)
    return [:skip, "html-only / no plain body"] if body.nil? || body.empty?

    min = Integer(ENV.fetch("BODY_MIN_CHARS", "5"))
    max = Integer(ENV.fetch("BODY_MAX_CHARS", "1500"))
    return [:skip, "body too short (#{body.length} < #{min})"] if body.length < min
    return [:skip, "body too long (#{body.length} > #{max})"]  if body.length > max

    [:print]
  end

  def self.plain_body(mail)
    part = mail.multipart? ? mail.text_part : mail
    return nil unless part

    body = part.decoded.to_s
    body.strip
  end
end
