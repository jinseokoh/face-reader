import type { ReactNode } from "react";
import { Link } from "react-router";

/**
 * 사용자 이름(닉네임 등)을 감싸 해당 사용자 show 페이지로 이동시키는 링크.
 * id 가 없으면(anon 등) 링크 없이 children 만 렌더.
 */
export const UserLink = ({
  id,
  children,
}: {
  id?: string | null;
  children: ReactNode;
}) => {
  if (!id) return <>{children}</>;
  return (
    <Link
      to={`/users/show/${id}`}
      onClick={(e) => e.stopPropagation()}
      style={{ cursor: "pointer" }}
    >
      {children}
    </Link>
  );
};
