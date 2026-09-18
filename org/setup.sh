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

log "1. 조직 프로필·회원 권한 정책"
gh api -X PATCH "orgs/$ORG" \
  -f name='IndexFinger Lab' \
  -f description='IndexFinger의 실험·연구 조직' \
  -f default_repository_permission=read \
  -F members_can_create_public_repositories=false \
  -F members_can_create_private_repositories=true \
  -F members_can_fork_private_repositories=false \
  -F members_can_create_pages=false \
  -F members_can_create_public_pages=false \
  -F members_can_create_private_pages=false \
  >/dev/null
echo "   기본 레포 권한 read · 공개 레포 생성 금지 · 비공개 포크 금지 · Pages 금지"

log "2. GitHub Actions 정책"
gh api -X PUT "orgs/$ORG/actions/permissions" \
  -f enabled_repositories=all -f allowed_actions=selected >/dev/null
gh api -X PUT "orgs/$ORG/actions/permissions/selected-actions" --input - <<'EOF' >/dev/null
{"github_owned_allowed": true, "verified_allowed": true, "patterns_allowed": []}
EOF
gh api -X PUT "orgs/$ORG/actions/permissions/workflow" \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false >/dev/null
echo "   GitHub 제작·검증된 액션만 허용 · 워크플로 기본 토큰 read-only · 봇의 PR 승인 금지"

log "3. 팀 core (CODEOWNERS 기본 리뷰어)"
if ! gh api "orgs/$ORG/teams/core" >/dev/null 2>&1; then
  gh api -X POST "orgs/$ORG/teams" \
    -f name=core -f description='코어 메인테이너 — CODEOWNERS 기본 리뷰어' \
    -f privacy=closed -f notification_setting=notifications_enabled >/dev/null
fi
gh api -X PUT "orgs/$ORG/teams/core/memberships/$ME" -f role=maintainer >/dev/null
echo "   core 생성, $ME maintainer"

log "4. 코드 보안 기본 구성 → 새 레포에 자동 적용"
CFG_ID="$(gh api "orgs/$ORG/code-security/configurations" \
  --jq '.[] | select(.target_type=="organization" and .name=="lab-default") | .id')"
if [ -z "$CFG_ID" ]; then
  CFG_ID="$(gh api -X POST "orgs/$ORG/code-security/configurations" \
    --input "$HERE/code-security.json" --jq .id)"
fi
gh api -X PUT "orgs/$ORG/code-security/configurations/$CFG_ID/defaults" \
  -f default_for_new_repos=all >/dev/null
echo "   lab-default (id $CFG_ID): Dependabot 알림·보안 업데이트·의존성 그래프·시크릿 스캐닝+푸시 보호"

log "5. 조직 전체 기본 브랜치 보호 룰셋"
RS_ID="$(gh api "orgs/$ORG/rulesets" --jq '.[] | select(.name=="default-branch-protection") | .id' 2>/dev/null || true)"
if [ -z "$RS_ID" ]; then
  try gh api -X POST "orgs/$ORG/rulesets" --input "$HERE/rulesets/default-branch.json" >/dev/null
else
  try gh api -X PUT "orgs/$ORG/rulesets/$RS_ID" --input "$HERE/rulesets/default-branch.json" >/dev/null
fi
echo "   삭제·force-push 금지 · PR 필수(승인 1, 코드오너, 스레드 해결, stale 승인 무효) · 조직 관리자는 우회"
echo "   (주의: Free 플랜에서는 공개 레포에만 강제된다 — 비공개 레포까지 강제하려면 Team 플랜)"

log "6. .github 레포 (프로필·템플릿·CODEOWNERS·이 스크립트)"
if ! gh repo view "$ORG/.github" >/dev/null 2>&1; then
  (cd "$HERE/.." && gh repo create "$ORG/.github" --public --source . --push \
     --description 'IndexFinger Lab 조직 프로필·기본 템플릿·조직 설정(config-as-code)')
else
  (cd "$HERE/.." && git push -u origin HEAD)
fi

log "7. 사람이 웹에서 해야 하는 것 (API 없음)"
cat <<EOF
   - 2FA 필수화:         https://github.com/organizations/$ORG/settings/security
   - 도메인 검증(선택):  https://github.com/organizations/$ORG/settings/domains
   - 요금제(비공개 레포 룰셋 강제가 필요할 때 Team): https://github.com/organizations/$ORG/billing/plans
EOF

log "검증"
gh api "orgs/$ORG" --jq '"   default_repo_permission=" + .default_repository_permission + " public_create=" + (.members_can_create_public_repositories|tostring) + " fork_private=" + (.members_can_fork_private_repositories|tostring) + " 2fa_required=" + (.two_factor_requirement_enabled|tostring)'
gh api "orgs/$ORG/actions/permissions/workflow" --jq '"   workflow_token=" + .default_workflow_permissions'
gh api "orgs/$ORG/rulesets" --jq '.[] | "   ruleset " + .name + " " + .enforcement' 2>/dev/null || true
gh api "orgs/$ORG/teams" --jq '.[] | "   team " + .slug'
