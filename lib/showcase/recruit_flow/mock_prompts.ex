defmodule Showcase.RecruitFlow.MockPrompts do
  @moduledoc """
  Curated scenarios for RecruitFlow.

  * `phone_scenarios/0` — candidates with canned phone-screen responses (one
    per outcome: qualified / not_qualified / callback / needs_human).
  * `cv_match_scenarios/0` — CV bodies + expected matching info.

  Consumed by Seed + test setup via `RecruitFlow.register_mock_responses/0`.
  """

  @phone_scenarios [
    %{
      name: "alice_qualified",
      candidate: %{name: "Alice Anderson", email: "alice@example.com", phone: "+1-555-0101"},
      position_title: "Software Engineer",
      claude_response: ~s({"transcript": "Interviewer: Tell me about your background. Alice: I've shipped 3 production Elixir services and led a team of 4. Interviewer: Why this role? Alice: I want to work on AI-mediated tooling.", "outcome": "qualified", "reasoning": "Strong Elixir + leadership + alignment with role intent.", "score": 0.92})
    },
    %{
      name: "bob_not_qualified",
      candidate: %{name: "Bob Brown", email: "bob@example.com", phone: "+1-555-0102"},
      position_title: "Software Engineer",
      claude_response: ~s({"transcript": "Interviewer: Tell me about your background. Bob: I have 2 years of HTML experience.", "outcome": "not_qualified", "reasoning": "HTML-only background; role requires backend Elixir.", "score": 0.18})
    },
    %{
      name: "carol_callback",
      candidate: %{name: "Carol Chen", email: "carol@example.com", phone: "+1-555-0103"},
      position_title: "Software Engineer",
      claude_response: ~s({"transcript": "Interviewer: Are you available next week? Carol: I'm at a wedding. Can you call me back Friday?", "outcome": "callback", "reasoning": "Candidate requested specific callback time; not assessed yet.", "score": 0.5})
    },
    %{
      name: "dan_needs_human",
      candidate: %{name: "Dan Davies", email: "dan@example.com", phone: "+1-555-0104"},
      position_title: "Software Engineer",
      claude_response: ~s({"transcript": "Interviewer: What's your experience? Dan: I'm a senior IC at a unicorn but considering management.", "outcome": "needs_human", "reasoning": "Senior IC vs management path is a recruiter judgment call.", "score": 0.6})
    }
  ]

  @cv_match_scenarios [
    %{
      name: "alice_cv_email_match",
      pdf_text: "Alice Anderson — Senior Engineer, 5 years Elixir, 3 years Phoenix...",
      candidate_email: "alice@example.com",
      candidate_phone: nil,
      subject_line: "Alice Anderson CV"
    },
    %{
      name: "carol_cv_subject_match",
      pdf_text: "Carol Chen — Backend developer, Python + Elixir, 4 years experience...",
      candidate_email: "carol.different@gmail.com",
      candidate_phone: nil,
      subject_line: "RE: Application #C-103"
    },
    %{
      name: "dan_cv_fuzzy_match",
      pdf_text: "Daniel Davies — Senior IC at unicorn. Looking to transition...",
      candidate_email: "dan.work@example.com",
      candidate_phone: nil,
      subject_line: "CV submission"
    }
  ]

  def phone_scenarios, do: @phone_scenarios
  def cv_match_scenarios, do: @cv_match_scenarios
end
