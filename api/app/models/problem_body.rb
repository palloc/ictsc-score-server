# frozen_string_literal: true

class ProblemBody < ApplicationRecord
  validates :mode,          presence: true
  validates :title,         presence: true
  validates :text,          presence: true, length: { maximum: 8192 }
  validates :perfect_point, presence: true
  validates :problem,       presence: true
  validates :candidates,    presence: false
  validates :corrects,      presence: false

  belongs_to :problem

  enum mode: {
    textbox: 10,
    radio_button: 20,
    checkbox: 30
  }

  # after_commit :regrade_answers
  # candidatesが変更されると既存のanswerのbodiesが矛盾する
  #   delay中のanswerが無ければ無視しても良い
  #   delay中のanswerがある場合にcandidatesの変更があると不公平が生じる可能性がある

  validate :validate_problem_body_format

  # dirty...
  def validate_problem_body_format # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    # ProblemBodyを登録するのは信用できるユーザーのみなので、ここまでしなくても良いかもしれない
    case mode
    when 'textbox'
      errors.add(:candidates, "in #{mode} mode, candidates must be nil") unless candidates.nil?
      errors.add(:corrects, "in #{mode} mode, corrects must be nil") unless corrects.nil?
    when 'radio_button', 'checkbox'
      if candidates.blank?
        errors.add(:candidates, "in #{mode} mode, candidates must not be blank")
      elsif !candidates.all?(Array) || !candidates.all?(&:present?) || !candidates.all? {|arr| arr.all?(String) }
        errors.add(:candidates, "in #{mode} mode, candidates elements must be Array of String")
      end

      if corrects.blank?
        errors.add(:corrects, "in #{mode} mode, corrects must not be blank")
      elsif !corrects.all?(Array) || !corrects.all?(&:present?) || !corrects.all? {|arr| arr.all?(String) }
        errors.add(:corrects, "in #{mode} mode, corrects elements must be Array of String")
      end

      return if errors.key?(:candidates) || errors.key?(:corrects)

      unless candidates.size == corrects.size
        errors.add(:corrects, 'corrects size must be same as candidates size')
        return
      end

      if mode == 'radio_button'
        if corrects.any? {|correct| correct.size > 1 }
          errors.add(:corrects, "in #{mode} mode, each correct elements size must be one")
        elsif corrects.zip(candidates).any? {|correct, candidate| !candidate.include?(correct.first) }
          errors.add(:corrects, "in #{mode} mode, correct must be included in candidates")
        end
      else
        # rubocop:disable Style/IfInsideElse
        if corrects.zip(candidates).any? {|correct, candidate| correct.size > candidate.size }
          errors.add(:corrects, "in #{mode} mode, each correct elements size must be less or equal candidate size")
        elsif corrects.zip(candidates).any? {|correct, candidate| !(correct - candidate).empty? }
          errors.add(:corrects, "in #{mode} mode, correct must be included candidates")
        end
        # rubocop:enable Style/IfInsideElse
      end
    else
      raise ProblemBodyUnhandledMode, mode
    end
  end

  # TODO: candidatesやcorrectsがupdateされたら、関連する問題は再採点が必要 毎回採点したほうが良いかもしれない
end
