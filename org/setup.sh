#!/usr/bin/env bash
# IndexFinger Lab — GitHub 조직 기업급 세팅 (멱등: 몇 번 돌려도 같은 결과)
# 전제: 조직이 이미 존재하고, gh 토큰에 admin:org 스코프가 있다.
#   gh auth refresh -h github.com -s admin:org
set -euo pipefail

ORG="${ORG:-indexfinger-lab}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ME="$(gh api user --jq .login)"

log() { printf '\n== %s\n' "$*"; }
try() { "$@" || echo "   !! 실패 (계속 진행): $*" >&2; }

log "0. 조직 존재·권한 확인 ($ORG, 실행자 $ME)"
gh api "orgs/$ORG" --jq '"   " + .login + " / plan=" + .plan.name' || { echo "조직이 없습니다. 웹에서 먼저 만드세요: https://github.com/organizations/plan"; exit 1; }
gh api "user/memberships/orgs/$ORG" --jq '"   role=" + .role'

log "1. 조직 프로필 (소규모 팀 — 회원 권한 제한은 두지 않는다)"
gh api -X PATCH "orgs/$ORG" \
  -f name='IndexFinger Lab' \
  -f description='IndexFinger의 실험·연구 조직' \
  -f default_repository_permission=write \
  >/dev/null
echo "   기본 레포 권한 write · 레포 생성·포크·Pages 제한 없음"

log "2. GitHub Actions 정책 (서드파티 액션 공급망 방어)"
try gh api -X PUT "orgs/$ORG/actions/permissions" \
  -f enabled_repositories=all -f allowed_actions=selected >/dev/null
try gh api -X PUT "orgs/$ORG/actions/permissions/selected-actions" --input - <<'EOF' >/dev/null
{"github_owned_allowed": true, "verified_allowed": true, "patterns_allowed": []}
EOF
try gh api -X PUT "orgs/$ORG/actions/permissions/workflow" \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false >/dev/null
echo "   GitHub 제작·검증된 액션만 허용 · 워크플로 기본 토큰 read-only"

log "3. 팀 core (CODEOWNERS 자동 리뷰 요청용)"
if ! gh api "orgs/$ORG/teams/core" >/dev/null 2>&1; then
  try gh api -X POST "orgs/$ORG/teams" \
    -f name=core -f description='코어 메인테이너 — CODEOWNERS 기본 리뷰어' \
    -f privacy=closed -f notification_setting=notifications_enabled >/dev/null
fi
try gh api -X PUT "orgs/$ORG/teams/core/memberships/$ME" -f role=maintainer >/dev/null
echo "   core 생성, $ME maintainer"

log "4. 코드 보안 기본 구성 → 새 레포에 자동 적용 (시크릿 유출·취약 의존성 방지)"
CFG_ID="$(gh api "orgs/$ORG/code-security/configurations" \
  --jq '.[] | select(.target_type=="organization" and .name=="lab-default") | .id' 2>/dev/null || true)"
if [ -z "$CFG_ID" ]; then
  CFG_ID="$(gh api -X POST "orgs/$ORG/code-security/configurations" \
    --input "$HERE/code-security.json" --jq .id 2>/dev/null || true)"
fi
if [ -n "$CFG_ID" ]; then
  try gh api -X PUT "orgs/$ORG/code-security/configurations/$CFG_ID/defaults" \
    -f default_for_new_repos=all >/dev/null
  echo "   lab-default (id $CFG_ID): Dependabot 알림·보안 업데이트·의존성 그래프·시크릿 스캐닝+푸시 보호"
else
  echo "   !! 코드 보안 구성 생성 실패 (admin:org 스코프 필요)" >&2
fi

log "5. 조직 전체 기본 브랜치 보호 룰셋 (실수 방지: 삭제·force-push만 막는다)"
RS_ID="$(gh api "orgs/$ORG/rulesets" --jq '.[] | select(.name=="default-branch-protection") | .id' 2>/dev/null || true)"
if [ -z "$RS_ID" ]; then
  try gh api -X POST "orgs/$ORG/rulesets" --input "$HERE/rulesets/default-branch.json" >/dev/null
else
  try gh api -X PUT "orgs/$ORG/rulesets/$RS_ID" --input "$HERE/rulesets/default-branch.json" >/dev/null
fi
echo "   기본 브랜치 삭제·force-push 금지 · 직접 push·PR 리뷰 여부는 자유"
echo "   (Free 플랜에서는 공개 레포에만 강제된다 — 비공개 레포까지 강제하려면 Team 플랜)"

log "6. .github 레포 (프로필·템플릿·CODEOWNERS·이 스크립트)"
if ! gh repo view "$ORG/.github" >/dev/null 2>&1; then
  (cd "$HERE/.." && gh repo create "$ORG/.github" --private --source . --push \
     --description 'IndexFinger Lab 조직 프로필·기본 템플릿·조직 설정(config-as-code)')
else
  (cd "$HERE/.." && git push -u origin HEAD)
fi

log "7. 선택 사항 (웹)"
echo "   - 요금제(비공개 레포 룰셋 강제가 필요할 때 Team): https://github.com/organizations/$ORG/billing/plans"

log "검증"
gh api "orgs/$ORG" --jq '"   default_repo_permission=" + .default_repository_permission'
gh api "orgs/$ORG/actions/permissions/workflow" --jq '"   workflow_token=" + .default_workflow_permissions' 2>/dev/null || echo "   workflow_token=(조회 불가)"
gh api "orgs/$ORG/rulesets" --jq '.[] | "   ruleset " + .name + " " + .enforcement' 2>/dev/null || true
gh api "orgs/$ORG/teams" --jq '.[] | "   team " + .slug' 2>/dev/null || true
