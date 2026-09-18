# indexfinger-lab/.github

조직 공통 자산. 이 레포의 템플릿·정책 파일은 조직의 모든 레포에 기본 상속된다 (레포에 같은 파일이 있으면 그쪽이 우선).

| 경로 | 역할 |
|---|---|
| `assets/avatar.png` | 조직 아바타 원본 (조직 설정에 업로드). 프로필 README·배너는 `.github-private` 레포 |
| `CODEOWNERS` | 이 레포의 기본 리뷰어 (`@indexfinger-lab/core`) |
| `CONTRIBUTING.md` · `SECURITY.md` | 기여·보안 제보 안내 (전 레포 상속) |
| `PULL_REQUEST_TEMPLATE.md` · `ISSUE_TEMPLATE/` | PR·이슈 템플릿 (전 레포 상속) |
| `org/setup.sh` | 조직 설정 config-as-code — 권한·Actions·팀·코드 보안·룰셋. 멱등, 재실행 가능 |

## 조직 설정 다시 적용하기

```bash
gh auth refresh -h github.com -s admin:org   # 최초 1회
bash org/setup.sh
```
