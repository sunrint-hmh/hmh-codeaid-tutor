#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "open3"
require "rbconfig"
require "yaml"

ROOT = File.expand_path("../..", __dir__)

REQUIRED_PATHS = %w[
  SKILL.md
  agents/openai.yaml
  01_커스텀_가능/내_설정.md
  01_커스텀_가능/사용법/01_시작하기.md
  01_커스텀_가능/사용법/02_질문_예시.md
  01_커스텀_가능/배포/공지_초안.md
  02_절대_불가능/필수_튜터_규칙.md
  02_절대_불가능/모드와_힌트_단계.md
  02_절대_불가능/배포/build_portable_prompt.rb
  02_절대_불가능/배포/핵심_프롬프트_복붙용.txt
  02_절대_불가능/검증/검증_시나리오.md
  02_절대_불가능/검증/검증_기록.md
  02_절대_불가능/검증/validate_harness.rb
  02_절대_불가능/참고자료/CodeAid_참고자료.md
].freeze

LEGACY_PATHS = %w[
  00_시작하기.md
  01_내_설정.md
  02_필수_튜터_규칙.md
  03_핵심_프롬프트_복붙용.txt
  04_질문_예시.md
  공지_초안.md
  references
  03_사용법_및_세부사항
].freeze

ALLOWED_ROOT_ENTRIES = %w[
  SKILL.md
  agents
  01_커스텀_가능
  02_절대_불가능
].freeze

SETTINGS = [
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

failures = []

unexpected_root_entries = Dir.children(ROOT).reject do |entry|
  ALLOWED_ROOT_ENTRIES.include?(entry)
end
unexpected_root_entries.each do |entry|
  failures << "unexpected root entry: #{entry}"
end

REQUIRED_PATHS.each do |relative|
  path = File.join(ROOT, relative)
  failures << "missing or blank: #{relative}" unless File.file?(path) && !File.zero?(path)
end

LEGACY_PATHS.each do |relative|
  failures << "legacy path remains: #{relative}" if File.exist?(File.join(ROOT, relative))
end

skill_path = File.join(ROOT, "SKILL.md")
if File.file?(skill_path)
  skill = File.read(skill_path)
  match = skill.match(/\A---\s*\n(.*?)\n---\s*\n/m)
  if match
    frontmatter = YAML.safe_load(match[1])
    failures << "invalid skill name" unless frontmatter["name"] == "hmh-codeaid-tutor"
    description = frontmatter["description"].to_s
    failures << "description must start with 'Use when'" unless description.start_with?("Use when")
    failures << "description is too broad" if description.length > 500
  else
    failures << "SKILL.md frontmatter is missing"
  end
  failures << "SKILL.md should stay under 500 words" if skill.split.size >= 500
  %w[
    01_커스텀_가능/내_설정.md
    02_절대_불가능/필수_튜터_규칙.md
    02_절대_불가능/모드와_힌트_단계.md
    01_커스텀_가능/사용법/01_시작하기.md
    02_절대_불가능/배포/핵심_프롬프트_복붙용.txt
    02_절대_불가능/검증/검증_시나리오.md
    02_절대_불가능/참고자료/CodeAid_참고자료.md
  ].each do |relative|
    failures << "SKILL.md missing required path: #{relative}" unless skill.include?(relative)
  end
  %w[
    01_내_설정.md
    02_필수_튜터_규칙.md
    references/
  ].each do |legacy|
    failures << "SKILL.md still mentions legacy path: #{legacy}" if skill.include?(legacy)
  end
end

metadata_path = File.join(ROOT, "agents/openai.yaml")
if File.file?(metadata_path)
  metadata = YAML.safe_load(File.read(metadata_path))
  prompt = metadata.dig("interface", "default_prompt").to_s
  failures << "default_prompt does not invoke the skill" unless prompt.include?("$hmh-codeaid-tutor")
end

portable_path = File.join(ROOT, "02_절대_불가능/배포/핵심_프롬프트_복붙용.txt")
generator_path = File.join(ROOT, "02_절대_불가능/배포/build_portable_prompt.rb")
if File.file?(portable_path)
  portable = File.read(portable_path)
  SETTINGS.each do |setting|
    count = portable.lines.count { |line| line.match?(/\A#{Regexp.escape(setting)}:/) }
    failures << "portable prompt setting must appear once: #{setting} (found #{count})" unless count == 1
  end
  failures << "portable prompt misses the natural-language scaffold boundary" unless portable.include?("자연어 단계만으로도")
  failures << "portable prompt misses the single-request clarification rule" unless portable.include?("같은 정보를 다시 요구하지")
  failures << "portable prompt misses generated-file warning" unless portable.include?("단일 프롬프트")
  failures << "portable prompt misses setting interpretation guidance" unless portable.include?("[설정 해석 규칙]")
  failures << "portable prompt misses blank-setting behavior" unless portable.include?("프로젝트·언어·프레임워크가 비어 있으면")
  failures << "portable prompt misses protected-rule precedence" unless portable.include?("보호 규칙이 우선")
  failures << "portable prompt includes maintainer-only generation instructions" if portable.include?("build_portable_prompt.rb")
  failures << "portable prompt misses configured-language first-response rule" unless portable.include?("설정된 답변 언어와 말투")
  failures << "portable prompt misses the mandatory response-contract rule" unless portable.include?("첫 응답을 제외한 모든 답변은 아래 머리말과 네 필드를 모두 쓴다")
  failures << "portable prompt misses the no-duplicate handoff rule" unless portable.include?("보내기·말하기·답하기·적어 주기를 요구하지 않는다")
  failures << "portable prompt lets the action field consume the pending decision" unless portable.include?("선택·고르기·정하기·결정하기도 시키지 않는다")
  failures << "portable prompt misses the operational duplicate-request preflight" unless portable.include?("정보가 부족한 답변의 `직접 할 일`에 `보내`, `알려`, `말해`, `답해`, `적어`, `작성`이 있는가?")
  failures << "portable prompt misses the atomic-question preflight" unless portable.include?("`확인 질문`이 서로 다른 답 두 개 이상을 `와`, `과`, `및`으로 묶었는가?")
  failures << "portable prompt contains a conflicting generated first-response block" if portable.include?("[단일 프롬프트 첫 응답]")
end

if File.file?(generator_path) && File.file?(portable_path)
  begin
    require generator_path
    expected = PortablePrompt.render(ROOT)
    actual = File.read(portable_path)
    failures << "portable prompt is out of sync (expected SHA-256 #{Digest::SHA256.hexdigest(expected)})" unless actual == expected

    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      generator_path,
      "--check",
      chdir: ROOT
    )
    check_mode_valid = status.success? && stdout.start_with?("PASS:") && stderr.empty?
    failures << "portable prompt generator --check mode is missing or invalid" unless check_mode_valid
  rescue StandardError => error
    failures << "portable prompt generation failed: #{error.message}"
  end
end

Dir.glob(File.join(ROOT, "**", "*.{md,txt}")).each do |path|
  File.read(path).scan(/\[[^\]]+\]\(([^)]+)\)/).flatten.each do |link|
    next if link.match?(%r{\Ahttps?://})

    target = File.expand_path(link.split("#", 2).first, File.dirname(path))
    failures << "broken local link: #{path.delete_prefix("#{ROOT}/")} -> #{link}" unless File.exist?(target)
  end
end

if failures.empty?
  puts "PASS: harness structure, metadata, links, settings, and portable prompt are valid"
  exit 0
end

warn "FAIL: #{failures.length} validation issue(s)"
failures.each { |failure| warn "- #{failure}" }
exit 1
