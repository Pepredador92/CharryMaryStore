import { supabase } from '../lib/supabase/client';

export const CATALOG_BUCKET = 'catalog-resources';

export type Product = {
  id: string;
  name: string;
  description: string | null;
  usage_instructions: string | null;
  warnings: string | null;
  updated_at: string;
};

export type Presentation = {
  id: string;
  product_id: string;
  sku: string;
  variant_label: string | null;
  attributes: Record<string, unknown> | null;
  current_price_amount_minor: number;
  currency_code: string;
  updated_at: string;
};

export type Inventory = {
  presentation_id: string;
  on_hand_quantity: number;
  updated_at: string;
};

export type Package = {
  id: string;
  name: string;
  description: string | null;
  current_price_amount_minor: number;
  currency_code: string;
  valid_from: string | null;
  valid_until: string | null;
  updated_at: string;
};

export type PackageComponent = {
  id: string;
  package_id: string;
  presentation_id: string;
  quantity: number;
  is_active: boolean;
};

export type CatalogResource = {
  id: string;
  product_id: string | null;
  presentation_id: string | null;
  package_id: string | null;
  source_reference: string;
  alt_text: string | null;
  sort_order: number;
  is_primary: boolean;
};

export type Classification = {
  id: string;
  name: string;
  parent_id: string | null;
};

export type ClassificationAssignment = {
  id: string;
  classification_id: string;
  product_id: string | null;
  package_id: string | null;
};

export type CatalogSnapshot = {
  products: Product[];
  presentations: Presentation[];
  inventory: Inventory[];
  packages: Package[];
  components: PackageComponent[];
  resources: CatalogResource[];
  classifications: Classification[];
  assignments: ClassificationAssignment[];
};

export type CartTarget = {
  kind: 'presentation' | 'package';
  id: string;
  name: string;
  detail: string;
  priceAmountMinor: number;
  currencyCode: string;
  availability: number;
  imageUrl: string | null;
  sellable: boolean;
};

type QueryResult<T> = { data: T | null; error: { message: string } | null };

function dataOrThrow<T>(result: QueryResult<T>, message: string): T {
  if (result.error) throw new Error(`${message}: ${result.error.message}`);
  return result.data ?? ([] as T);
}

export async function loadPublicCatalog(): Promise<CatalogSnapshot> {
  const [products, presentations, inventory, packages, components, resources, classifications, assignments] =
    await Promise.all([
      supabase.from('products').select('*').order('name'),
      supabase.from('sellable_presentations').select('*').order('sku'),
      supabase.from('presentation_inventory').select('*'),
      supabase.from('packages').select('*').order('name'),
      supabase.from('package_components').select('*').order('created_at'),
      supabase.from('catalog_resources').select('*').eq('resource_kind', 'image').order('sort_order'),
      supabase.from('commercial_classifications').select('*').order('name'),
      supabase.from('catalog_classification_assignments').select('*').order('created_at'),
    ]);

  return {
    products: dataOrThrow<Product[]>(products, 'No se pudo cargar Productos'),
    presentations: dataOrThrow<Presentation[]>(presentations, 'No se pudieron cargar Presentaciones'),
    inventory: dataOrThrow<Inventory[]>(inventory, 'No se pudo consultar disponibilidad'),
    packages: dataOrThrow<Package[]>(packages, 'No se pudieron cargar Paquetes'),
    components: dataOrThrow<PackageComponent[]>(components, 'No se pudieron cargar componentes'),
    resources: dataOrThrow<CatalogResource[]>(resources, 'No se pudieron cargar imagenes'),
    classifications: dataOrThrow<Classification[]>(classifications, 'No se pudieron cargar clasificaciones'),
    assignments: dataOrThrow<ClassificationAssignment[]>(assignments, 'No se pudieron cargar asignaciones'),
  };
}

export function catalogResourceUrl(resource: CatalogResource | undefined): string | null {
  if (!resource) return null;
  return supabase.storage.from(CATALOG_BUCKET).getPublicUrl(resource.source_reference).data.publicUrl;
}

export function primaryResource(
  snapshot: CatalogSnapshot,
  kind: 'product' | 'presentation' | 'package',
  id: string,
): CatalogResource | undefined {
  return catalogResources(snapshot, kind, id)[0];
}

export function catalogResources(
  snapshot: CatalogSnapshot,
  kind: 'product' | 'presentation' | 'package',
  id: string,
): CatalogResource[] {
  const column = `${kind}_id` as 'product_id' | 'presentation_id' | 'package_id';
  return snapshot.resources
    .filter((resource) => resource[column] === id)
    .sort((left, right) => Number(right.is_primary) - Number(left.is_primary) || left.sort_order - right.sort_order);
}

export function presentationAvailability(snapshot: CatalogSnapshot, presentationId: string): number {
  return snapshot.inventory.find((item) => item.presentation_id === presentationId)?.on_hand_quantity ?? 0;
}

export function packageAvailability(snapshot: CatalogSnapshot, packageId: string): number {
  const components = snapshot.components.filter((item) => item.package_id === packageId && item.is_active);
  if (!components.length) return 0;
  return Math.min(
    ...components.map((component) =>
      Math.floor(presentationAvailability(snapshot, component.presentation_id) / component.quantity),
    ),
  );
}

export function resolveCartTarget(
  snapshot: CatalogSnapshot,
  kind: 'presentation' | 'package',
  id: string,
): CartTarget | null {
  if (kind === 'presentation') {
    const presentation = snapshot.presentations.find((item) => item.id === id);
    if (!presentation) return null;
    const product = snapshot.products.find((item) => item.id === presentation.product_id);
    if (!product) return null;
    const availability = presentationAvailability(snapshot, id);
    const resource = primaryResource(snapshot, 'presentation', id) ?? primaryResource(snapshot, 'product', product.id);
    return {
      kind,
      id,
      name: product.name,
      detail: presentation.variant_label || presentation.sku,
      priceAmountMinor: presentation.current_price_amount_minor,
      currencyCode: presentation.currency_code,
      availability,
      imageUrl: catalogResourceUrl(resource),
      sellable: availability > 0,
    };
  }

  const itemPackage = snapshot.packages.find((item) => item.id === id);
  if (!itemPackage) return null;
  const availability = packageAvailability(snapshot, id);
  return {
    kind,
    id,
    name: itemPackage.name,
    detail: 'Paquete',
    priceAmountMinor: itemPackage.current_price_amount_minor,
    currencyCode: itemPackage.currency_code,
    availability,
    imageUrl: catalogResourceUrl(primaryResource(snapshot, 'package', id)),
    sellable: availability > 0,
  };
}

export function formatMoney(amountMinor: number, currencyCode = 'MXN'): string {
  return new Intl.NumberFormat('es-MX', { style: 'currency', currency: currencyCode }).format(amountMinor / 100);
}
