alter table actions drop column src, drop column srcmd5;

alter table action_inputs drop column destination;

-- can't drop the type, function inargscheck still uses that
