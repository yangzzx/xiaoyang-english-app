-- 若 13 提示缺少结构，或云端实际表现与客户端不一致，请运行本只读脚本。
-- 仅导出结构、函数和索引定义；不导出用户表数据、邮箱或凭据。
select table_name,column_name,data_type,is_nullable,column_default
from information_schema.columns
where table_schema='public' and table_name in ('day32_progress','day32_lessons','day32_reviews','study_records','study_reviews','study_word_reviews')
order by table_name,ordinal_position;

select c.relname as table_name,con.conname,pg_get_constraintdef(con.oid) as definition
from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relname in ('day32_lessons','day32_reviews','study_reviews','study_word_reviews');

select tablename,indexname,indexdef from pg_indexes where schemaname='public'
and tablename in ('day32_lessons','day32_reviews','study_reviews','study_word_reviews');

select p.proname,pg_get_function_identity_arguments(p.oid) as arguments,pg_get_functiondef(p.oid) as definition
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in ('day32_complete','day32_grade','day32_grade_day','day32_review_manage','study_word_sync','study_word_grade','study_review_interval','study_review_version','study_spell_answer');
