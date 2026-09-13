import ts from 'typescript';
import { validateArtifactPath } from './snapshot.mjs';

export function validateContractBindings({ sourceText, sources, roots }) {
  if (!Array.isArray(sources) || !sources.length || !Array.isArray(roots) || !roots.length) {
    throw new Error('SDK sources and roots must be nonempty arrays');
  }
  if (new Set(sources.map(({ id }) => id)).size !== sources.length
    || new Set(roots.map(({ name }) => name)).size !== roots.length
    || new Set(roots.map(({ schema }) => schema)).size !== roots.length) {
    throw new Error('SDK source IDs, root names, and schema paths must be unique');
  }
  const sourcePackages = new Map();
  for (const source of sources) {
    if (!/^[a-z][a-z0-9-]*$/.test(source.id)
      || !/^(?:@[a-z0-9-]+\/)?[a-z][a-z0-9._-]*$/.test(source.package)) {
      throw new Error(`Invalid SDK source: ${source.id}`);
    }
    validateArtifactPath(source.noticeFile);
    sourcePackages.set(source.id, source.package);
  }
  const imports = new Map();
  const aliases = new Map();
  const source = ts.createSourceFile('contracts.ts', sourceText, ts.ScriptTarget.ES2022, true);
  for (const statement of source.statements) {
    if (ts.isImportDeclaration(statement)) {
      const clause = statement.importClause;
      if (!clause?.isTypeOnly || !clause.namedBindings || !ts.isNamespaceImport(clause.namedBindings)) {
        throw new Error('SDK declarations require type-only namespace imports');
      }
      imports.set(clause.namedBindings.name.text, statement.moduleSpecifier.text);
    } else if (ts.isTypeAliasDeclaration(statement)) {
      aliases.set(statement.name.text, statement.type);
    } else if (!ts.isInterfaceDeclaration(statement)) {
      throw new Error('contracts.ts may contain only type-only imports, aliases, and interfaces');
    }
  }
  for (const root of roots) {
    validateArtifactPath(root.schema);
    if (!root.schema.endsWith('.schema.json') || root.schema === 'PresenceProbe.schema.json') {
      throw new Error(`Invalid or reserved schema output: ${root.schema}`);
    }
    const alias = aliases.get(root.name);
    const packageName = sourcePackages.get(root.sdk);
    if (!packageName || !alias || !ts.isTypeReferenceNode(alias) || !ts.isQualifiedName(alias.typeName)
      || !ts.isIdentifier(alias.typeName.left) || alias.typeArguments?.length
      || imports.get(alias.typeName.left.text) !== `${packageName}/${root.module}`
      || alias.typeName.right.text !== root.export) {
      throw new Error(`SDK root provenance does not match its type-only binding: ${root.name}`);
    }
    validateArtifactPath(root.module);
  }
}
