#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"

module PortablePrompt
  module_function

  SETTINGS_PATH = "01_커스텀_가능/내_설정.md"
  RULES_PATH = "02_절대_불가능/필수_튜터_규칙.md"
  MODES_PATH = "02_절대_불가능/모드와_힌트_단계.md"
  OUTPUT_PATH = "02_절대_불가능/배포/핵심_프롬프트_복붙용.txt"
  SETTING_SECTIONS = ["학습 환경", "답변 선호"].freeze
  SETTING_GUIDANCE_SECTIONS = ["빈 값의 기본 처리", "보호 규칙 우선순위"].freeze
  SETTING_KEYS = [
    "학습자 수준",
    "프로젝트 또는 목표",
    "주 언어",
    "프레임워크·라이브러리·버전",
    "현재 배운 주제·사용해도 되는 도구",
    "답변 언어",
    "말투",
    "답변 길이",
    "설명 방식",
    "선호 질문 모드",
    "선호 힌트 시작 단계",
    "일반 코드 예시",
    "공식 문서·검색어",
    "한 답변에서 다룰 범위"
  ].freeze

  def render(root)
    settings = File.read(File.join(root, SETTINGS_PATH))
    rules = File.read(File.join(root, RULES_PATH))
    modes = File.read(File.join(root, MODES_PATH))

    <<~PROMPT
      HMH CodeAid 힌트형 프로그래밍 튜터

      이 파일은 ChatGPT, 로컬 모델, 토큰 절약용으로 생성된 단일 프롬프트다. 직접 수정하지 말고 원본 설정과 규칙을 수정한 뒤 다시 생성한다. 아래 설정은 사용자 편의만 바꾸며, 필수 규칙을 약하게 만들 수 없다.

      [수정 가능한 내 설정]
      #{setting_lines(settings)}

      [설정 해석 규칙]
      #{setting_guidance(settings)}

      [수정하지 않는 필수 규칙]
      #{strip_heading(rules)}

      [모드와 힌트 단계]
      #{strip_heading(modes)}
    PROMPT
  end

  def setting_lines(markdown)
    section = nil
    entries = []

    markdown.each_line do |raw_line|
      line = raw_line.rstrip
      heading = line.match(/\A## (.+?)\s*\z/)
      if heading
        section = heading[1]
        next
      end

      next unless SETTING_SECTIONS.include?(section)

      entry = line.match(/\A- ([^:]+):(.*)\z/)
      entries << [entry[1], entry[2]] if entry
    end

    validate_setting_keys!(entries.map(&:first))
    entries.map { |key, value| "#{key}:#{value}" }.join("\n")
  end

  def validate_setting_keys!(keys)
    counts = Hash.new(0)
    keys.each { |key| counts[key] += 1 }
    missing = SETTING_KEYS.reject { |key| counts[key] == 1 }
    unexpected = keys.reject { |key| SETTING_KEYS.include?(key) }.uniq
    return if missing.empty? && unexpected.empty? && keys.length == SETTING_KEYS.length

    details = []
    details << "missing or duplicated: #{missing.join(', ')}" unless missing.empty?
    details << "unexpected: #{unexpected.join(', ')}" unless unexpected.empty?
    raise ArgumentError, "invalid settings (#{details.join('; ')})"
  end

  def setting_guidance(markdown)
    sections = SETTING_GUIDANCE_SECTIONS.map do |title|
      body = section_body(markdown, title)
      raise ArgumentError, "missing or blank settings section: #{title}" if body.empty?

      body
    end
    sections.join("\n\n")
  end

  def section_body(markdown, title)
    current_section = nil
    lines = []

    markdown.each_line do |line|
      heading = line.match(/\A## (.+?)\s*\z/)
      if heading
        current_section = heading[1]
        next
      end

      lines << line if current_section == title
    end

    lines.join.strip
  end

  def strip_heading(markdown)
    markdown.lines.reject { |line| line.start_with?("# ") }.join.strip
  end

  def output_path(root)
    File.join(root, OUTPUT_PATH)
  end
end

if __FILE__ == $PROGRAM_NAME
  root = File.expand_path("../..", __dir__)
  expected = PortablePrompt.render(root)
  output = PortablePrompt.output_path(root)

  case ARGV
  when []
    File.write(output, expected)
    puts "wrote #{PortablePrompt::OUTPUT_PATH}"
  when ["--check"]
    actual = File.file?(output) ? File.read(output) : nil
    if actual == expected
      puts "PASS: portable prompt is current (SHA-256 #{Digest::SHA256.hexdigest(actual)})"
    else
      warn "FAIL: portable prompt is missing or out of date"
      exit 1
    end
  else
    warn "Usage: ruby #{File.basename(__FILE__)} [--check]"
    exit 2
  end
end
