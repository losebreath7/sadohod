"""Frozen R3 schema. Never import application models into a historical revision."""
import sqlalchemy as sa

metadata = sa.MetaData()

sa.Table('buyer_favorites', metadata,
    sa.Column('buyer', sa.String(length=32), primary_key=True, nullable=False),
    sa.Column('kind', sa.String(length=8), primary_key=True, nullable=False),
    sa.Column('item', sa.String(length=32), primary_key=True, nullable=False),
)

sa.Table('buyer_login_codes', metadata,
    sa.Column('email', sa.String(length=254), primary_key=True, nullable=False),
    sa.Column('digest', sa.String(length=128), primary_key=False, nullable=False),
    sa.Column('expires', sa.Float(), primary_key=False, nullable=False),
    sa.Column('sent', sa.Float(), primary_key=False, nullable=False),
    sa.Column('attempts', sa.Integer(), primary_key=False, nullable=False),
)

sa.Table('buyer_rate_buckets', metadata,
    sa.Column('key', sa.String(length=100), primary_key=True, nullable=False),
    sa.Column('count', sa.Integer(), primary_key=False, nullable=False),
    sa.Column('expires', sa.Float(), primary_key=False, nullable=False),
)

sa.Table('buyer_sessions', metadata,
    sa.Column('digest', sa.String(length=64), primary_key=True, nullable=False),
    sa.Column('buyer', sa.String(length=32), primary_key=False, nullable=False),
    sa.Column('expires', sa.Float(), primary_key=False, nullable=False),
)
sa.Index('ix_buyer_sessions_buyer', metadata.tables['buyer_sessions'].c['buyer'], unique=False)

sa.Table('buyers', metadata,
    sa.Column('id', sa.String(length=32), primary_key=True, nullable=False),
    sa.Column('email', sa.String(length=254), primary_key=False, nullable=False),
    sa.Column('name', sa.String(length=80), primary_key=False, nullable=False),
    sa.UniqueConstraint('email', name=None),
)

sa.Table('merchant_invitations', metadata,
    sa.Column('id', sa.String(length=32), primary_key=True, nullable=False),
    sa.Column('code_digest', sa.String(length=64), primary_key=False, nullable=False),
    sa.Column('email', sa.String(length=254), primary_key=False, nullable=False),
    sa.Column('shop_name', sa.String(length=120), primary_key=False, nullable=False),
    sa.Column('contact', sa.String(length=250), primary_key=False, nullable=False),
    sa.Column('zone', sa.String(length=160), primary_key=False, nullable=False),
    sa.Column('code', sa.String(length=32), primary_key=False, nullable=False),
    sa.Column('expires_at', sa.Float(), primary_key=False, nullable=False),
    sa.Column('used_at', sa.Float(), primary_key=False, nullable=True),
    sa.Column('created_at', sa.Float(), primary_key=False, nullable=False),
    sa.UniqueConstraint('code_digest', name=None),
)
sa.Index('ix_merchant_invitations_email', metadata.tables['merchant_invitations'].c['email'], unique=False)

sa.Table('pavilions', metadata,
    sa.Column('id', sa.String(length=32), primary_key=True, nullable=False),
    sa.Column('code', sa.String(length=32), primary_key=False, nullable=False),
    sa.Column('zone', sa.String(length=160), primary_key=False, nullable=False),
)

sa.Table('products', metadata,
    sa.Column('id', sa.String(length=32), primary_key=True, nullable=False),
    sa.Column('title', sa.String(length=160), primary_key=False, nullable=False),
    sa.Column('category', sa.String(length=80), primary_key=False, nullable=False),
    sa.Column('description', sa.Text(), primary_key=False, nullable=False),
    sa.Column('colors', sa.JSON(), primary_key=False, nullable=False),
    sa.Column('is_demo', sa.Boolean(), primary_key=False, nullable=False),
)
sa.Index('ix_products_category', metadata.tables['products'].c['category'], unique=False)
sa.Index('ix_products_title', metadata.tables['products'].c['title'], unique=False)

sa.Table('telegram_buyer_bridge_health_v0832', metadata,
    sa.Column('key', sa.String(length=24), primary_key=True, nullable=False),
    sa.Column('last_poll_at', sa.Float(), primary_key=False, nullable=False),
    sa.Column('last_update_at', sa.Float(), primary_key=False, nullable=False),
    sa.Column('last_reply_at', sa.Float(), primary_key=False, nullable=False),
    sa.Column('poll_count', sa.Integer(), primary_key=False, nullable=False),
    sa.Column('ignored_count', sa.Integer(), primary_key=False, nullable=False),
    sa.Column('error_count', sa.Integer(), primary_key=False, nullable=False),
    sa.Column('last_ignored_reason', sa.String(length=60), primary_key=False, nullable=False),
    sa.Column('last_error', sa.String(length=100), primary_key=False, nullable=False),
)

sa.Table('telegram_buyer_inbound_v083', metadata,
    sa.Column('chat_id', sa.String(length=24), primary_key=True, nullable=False),
    sa.Column('message_id', sa.Integer(), primary_key=True, nullable=False),
    sa.Column('created', sa.Float(), primary_key=False, nullable=False),
)

sa.Table('telegram_buyer_offset_v083', metadata,
    sa.Column('key', sa.String(length=32), primary_key=True, nullable=False),
    sa.Column('value', sa.Integer(), primary_key=False, nullable=False),
)

sa.Table('buyer_chat_attachments_v083', metadata,
    sa.Column('id', sa.String(length=32), primary_key=True, nullable=False),
    sa.Column('buyer', sa.String(length=32), sa.ForeignKey('buyers.id', ondelete=None), primary_key=False, nullable=False),
    sa.Column('message_id', sa.String(length=32), primary_key=False, nullable=False),
    sa.Column('filename', sa.String(length=128), primary_key=False, nullable=False),
    sa.Column('mime', sa.String(length=48), primary_key=False, nullable=False),
    sa.Column('raw', sa.LargeBinary(), primary_key=False, nullable=False),
    sa.Column('preview', sa.Text(), primary_key=False, nullable=False),
)
sa.Index('ix_buyer_chat_attachments_v083_buyer', metadata.tables['buyer_chat_attachments_v083'].c['buyer'], unique=False)
sa.Index('ix_buyer_chat_attachments_v083_message_id', metadata.tables['buyer_chat_attachments_v083'].c['message_id'], unique=False)

sa.Table('buyer_email_change_codes', metadata,
    sa.Column('buyer', sa.String(length=32), sa.ForeignKey('buyers.id', ondelete=None), primary_key=True, nullable=False),
    sa.Column('email', sa.String(length=254), primary_key=False, nullable=False),
    sa.Column('digest', sa.String(length=128), primary_key=False, nullable=False),
    sa.Column('expires', sa.Float(), primary_key=False, nullable=False),
    sa.Column('sent', sa.Float(), primary_key=False, nullable=False),
    sa.Column('attempts', sa.Integer(), primary_key=False, nullable=False),
)

sa.Table('buyer_messages', metadata,
    sa.Column('id', sa.String(length=32), primary_key=True, nullable=False),
    sa.Column('buyer', sa.String(length=32), sa.ForeignKey('buyers.id', ondelete=None), primary_key=False, nullable=False),
    sa.Column('kind', sa.String(length=16), primary_key=False, nullable=False),
    sa.Column('text', sa.Text(), primary_key=False, nullable=False),
    sa.Column('sent', sa.Float(), primary_key=False, nullable=False),
    sa.Column('staff', sa.Boolean(), primary_key=False, nullable=False),
)
sa.Index('ix_buyer_messages_buyer', metadata.tables['buyer_messages'].c['buyer'], unique=False)

sa.Table('buyer_profile_media', metadata,
    sa.Column('buyer', sa.String(length=32), sa.ForeignKey('buyers.id', ondelete=None), primary_key=True, nullable=False),
    sa.Column('avatar', sa.Text(), primary_key=False, nullable=False),
    sa.Column('cover', sa.Text(), primary_key=False, nullable=False),
)

sa.Table('product_category_state', metadata,
    sa.Column('product_id', sa.String(length=32), sa.ForeignKey('products.id', ondelete=None), primary_key=True, nullable=False),
    sa.Column('source', sa.String(length=24), primary_key=False, nullable=False),
    sa.Column('status', sa.String(length=32), primary_key=False, nullable=False),
    sa.Column('assigned', sa.String(length=80), primary_key=False, nullable=False),
    sa.Column('suggestion', sa.String(length=80), primary_key=False, nullable=False),
    sa.Column('score', sa.Float(), primary_key=False, nullable=False),
)

sa.Table('product_details', metadata,
    sa.Column('product_id', sa.String(length=32), sa.ForeignKey('products.id', ondelete=None), primary_key=True, nullable=False),
    sa.Column('active', sa.Boolean(), primary_key=False, nullable=False),
    sa.Column('sizes', sa.JSON(), primary_key=False, nullable=False),
)

sa.Table('product_images', metadata,
    sa.Column('id', sa.String(length=32), primary_key=True, nullable=False),
    sa.Column('product_id', sa.String(length=32), sa.ForeignKey('products.id', ondelete=None), primary_key=False, nullable=False),
    sa.Column('filename', sa.String(length=80), primary_key=False, nullable=False),
    sa.Column('descriptor', sa.JSON(), primary_key=False, nullable=False),
)
sa.Index('ix_product_images_product_id', metadata.tables['product_images'].c['product_id'], unique=False)

sa.Table('sellers', metadata,
    sa.Column('id', sa.String(length=32), primary_key=True, nullable=False),
    sa.Column('name', sa.String(length=120), primary_key=False, nullable=False),
    sa.Column('pavilion_id', sa.String(length=32), sa.ForeignKey('pavilions.id', ondelete=None), primary_key=False, nullable=False),
)

sa.Table('telegram_buyer_outbox_v083', metadata,
    sa.Column('id', sa.String(length=32), primary_key=True, nullable=False),
    sa.Column('buyer', sa.String(length=32), sa.ForeignKey('buyers.id', ondelete=None), primary_key=False, nullable=False),
    sa.Column('kind', sa.String(length=16), primary_key=False, nullable=False),
    sa.Column('message_id', sa.String(length=32), primary_key=False, nullable=False),
    sa.Column('sent', sa.Float(), primary_key=False, nullable=False),
    sa.Column('delivered', sa.Boolean(), primary_key=False, nullable=False),
    sa.Column('attempts', sa.Integer(), primary_key=False, nullable=False),
    sa.Column('retry_after', sa.Float(), primary_key=False, nullable=False),
)
sa.Index('ix_telegram_buyer_outbox_v083_buyer', metadata.tables['telegram_buyer_outbox_v083'].c['buyer'], unique=False)

sa.Table('telegram_buyer_topics_v083', metadata,
    sa.Column('buyer', sa.String(length=32), sa.ForeignKey('buyers.id', ondelete=None), primary_key=True, nullable=False),
    sa.Column('kind', sa.String(length=16), primary_key=True, nullable=False),
    sa.Column('chat_id', sa.String(length=24), primary_key=False, nullable=False),
    sa.Column('thread_id', sa.Integer(), primary_key=False, nullable=False),
    sa.Column('created', sa.Float(), primary_key=False, nullable=False),
    sa.UniqueConstraint('chat_id', 'thread_id', name='uq_v083_telegram_thread'),
)

sa.Table('buyer_seller_notes_v082', metadata,
    sa.Column('buyer', sa.String(length=32), sa.ForeignKey('buyers.id', ondelete=None), primary_key=True, nullable=False),
    sa.Column('seller', sa.String(length=32), sa.ForeignKey('sellers.id', ondelete=None), primary_key=True, nullable=False),
    sa.Column('text', sa.String(length=100), primary_key=False, nullable=False),
)

sa.Table('image_ml_embeddings', metadata,
    sa.Column('image_id', sa.String(length=32), sa.ForeignKey('product_images.id', ondelete='CASCADE'), primary_key=True, nullable=False),
    sa.Column('model_id', sa.String(length=140), primary_key=True, nullable=False),
    sa.Column('embedding', sa.JSON(), primary_key=False, nullable=False),
)

sa.Table('merchant_applications', metadata,
    sa.Column('id', sa.String(length=32), primary_key=True, nullable=False),
    sa.Column('buyer_id', sa.String(length=32), sa.ForeignKey('buyers.id', ondelete='CASCADE'), primary_key=False, nullable=False),
    sa.Column('shop_name', sa.String(length=120), primary_key=False, nullable=False),
    sa.Column('contact', sa.String(length=250), primary_key=False, nullable=False),
    sa.Column('zone', sa.String(length=160), primary_key=False, nullable=False),
    sa.Column('code', sa.String(length=32), primary_key=False, nullable=False),
    sa.Column('status', sa.String(length=16), primary_key=False, nullable=False),
    sa.Column('note', sa.Text(), primary_key=False, nullable=False),
    sa.Column('seller_id', sa.String(length=32), sa.ForeignKey('sellers.id', ondelete=None), primary_key=False, nullable=True),
    sa.Column('created_at', sa.Float(), primary_key=False, nullable=False),
)
sa.Index('ix_merchant_applications_buyer_id', metadata.tables['merchant_applications'].c['buyer_id'], unique=False)
sa.Index('ix_merchant_applications_status', metadata.tables['merchant_applications'].c['status'], unique=False)

sa.Table('merchant_memberships', metadata,
    sa.Column('buyer_id', sa.String(length=32), sa.ForeignKey('buyers.id', ondelete='CASCADE'), primary_key=True, nullable=False),
    sa.Column('seller_id', sa.String(length=32), sa.ForeignKey('sellers.id', ondelete=None), primary_key=False, nullable=False),
    sa.Column('role', sa.String(length=12), primary_key=False, nullable=False),
)
sa.Index('ix_merchant_memberships_seller_id', metadata.tables['merchant_memberships'].c['seller_id'], unique=False)

sa.Table('merchant_operations', metadata,
    sa.Column('seller_id', sa.String(length=32), sa.ForeignKey('sellers.id', ondelete=None), primary_key=True, nullable=False),
    sa.Column('request_id', sa.String(length=80), primary_key=True, nullable=False),
    sa.Column('digest', sa.String(length=64), primary_key=False, nullable=False),
    sa.Column('result', sa.JSON(), primary_key=False, nullable=False),
)

sa.Table('merchant_pavilion_claims', metadata,
    sa.Column('zone_key', sa.String(length=160), primary_key=True, nullable=False),
    sa.Column('code_key', sa.String(length=32), primary_key=True, nullable=False),
    sa.Column('seller_id', sa.String(length=32), sa.ForeignKey('sellers.id', ondelete=None), primary_key=False, nullable=False),
    sa.Column('pavilion_id', sa.String(length=32), sa.ForeignKey('pavilions.id', ondelete=None), primary_key=False, nullable=False),
    sa.Column('approved_at', sa.Float(), primary_key=False, nullable=False),
    sa.UniqueConstraint('pavilion_id', name=None),
)
sa.Index('ix_merchant_pavilion_claims_seller_id', metadata.tables['merchant_pavilion_claims'].c['seller_id'], unique=False)

sa.Table('merchant_pavilion_requests', metadata,
    sa.Column('id', sa.String(length=32), primary_key=True, nullable=False),
    sa.Column('seller_id', sa.String(length=32), sa.ForeignKey('sellers.id', ondelete=None), primary_key=False, nullable=False),
    sa.Column('zone', sa.String(length=160), primary_key=False, nullable=False),
    sa.Column('code', sa.String(length=32), primary_key=False, nullable=False),
    sa.Column('status', sa.String(length=16), primary_key=False, nullable=False),
    sa.Column('note', sa.Text(), primary_key=False, nullable=False),
    sa.Column('created_at', sa.Float(), primary_key=False, nullable=False),
)
sa.Index('ix_merchant_pavilion_requests_seller_id', metadata.tables['merchant_pavilion_requests'].c['seller_id'], unique=False)

sa.Table('merchant_products', metadata,
    sa.Column('product_id', sa.String(length=32), sa.ForeignKey('products.id', ondelete=None), primary_key=True, nullable=False),
    sa.Column('seller_id', sa.String(length=32), sa.ForeignKey('sellers.id', ondelete=None), primary_key=False, nullable=False),
    sa.Column('status', sa.String(length=16), primary_key=False, nullable=False),
    sa.Column('note', sa.Text(), primary_key=False, nullable=False),
    sa.Column('created_at', sa.Float(), primary_key=False, nullable=False),
)
sa.Index('ix_merchant_products_seller_id', metadata.tables['merchant_products'].c['seller_id'], unique=False)
sa.Index('ix_merchant_products_status', metadata.tables['merchant_products'].c['status'], unique=False)

sa.Table('merchant_shops', metadata,
    sa.Column('seller_id', sa.String(length=32), sa.ForeignKey('sellers.id', ondelete=None), primary_key=True, nullable=False),
    sa.Column('approved_at', sa.Float(), primary_key=False, nullable=False),
)

sa.Table('offers', metadata,
    sa.Column('id', sa.String(length=32), primary_key=True, nullable=False),
    sa.Column('product_id', sa.String(length=32), sa.ForeignKey('products.id', ondelete=None), primary_key=False, nullable=False),
    sa.Column('seller_id', sa.String(length=32), sa.ForeignKey('sellers.id', ondelete=None), primary_key=False, nullable=False),
    sa.Column('pavilion_id', sa.String(length=32), sa.ForeignKey('pavilions.id', ondelete=None), primary_key=False, nullable=False),
    sa.Column('price', sa.Integer(), primary_key=False, nullable=False),
)
sa.Index('ix_offers_product_id', metadata.tables['offers'].c['product_id'], unique=False)
sa.Index('ix_offers_seller_id', metadata.tables['offers'].c['seller_id'], unique=False)

sa.Table('product_image_order', metadata,
    sa.Column('image_id', sa.String(length=32), sa.ForeignKey('product_images.id', ondelete=None), primary_key=True, nullable=False),
    sa.Column('position', sa.Integer(), primary_key=False, nullable=False),
)

sa.Table('seller_details', metadata,
    sa.Column('seller_id', sa.String(length=32), sa.ForeignKey('sellers.id', ondelete=None), primary_key=True, nullable=False),
    sa.Column('contact', sa.String(length=500), primary_key=False, nullable=False),
    sa.Column('is_demo', sa.Boolean(), primary_key=False, nullable=False),
)

sa.Table('seller_reviews_v082', metadata,
    sa.Column('id', sa.String(length=32), primary_key=True, nullable=False),
    sa.Column('buyer', sa.String(length=32), sa.ForeignKey('buyers.id', ondelete=None), primary_key=False, nullable=False),
    sa.Column('seller', sa.String(length=32), sa.ForeignKey('sellers.id', ondelete=None), primary_key=False, nullable=False),
    sa.Column('rating', sa.Integer(), primary_key=False, nullable=False),
    sa.Column('text', sa.Text(), primary_key=False, nullable=False),
    sa.Column('photos', sa.JSON(), primary_key=False, nullable=False),
    sa.Column('hidden', sa.Boolean(), primary_key=False, nullable=False),
    sa.Column('reply', sa.Text(), primary_key=False, nullable=False),
    sa.Column('created_at', sa.Float(), primary_key=False, nullable=False),
    sa.Column('updated_at', sa.Float(), primary_key=False, nullable=False),
    sa.UniqueConstraint('buyer', 'seller', name='uq_v082_review_one_per_buyer'),
)
sa.Index('ix_seller_reviews_v082_buyer', metadata.tables['seller_reviews_v082'].c['buyer'], unique=False)
sa.Index('ix_seller_reviews_v082_seller', metadata.tables['seller_reviews_v082'].c['seller'], unique=False)

sa.Table('merchant_listings', metadata,
    sa.Column('id', sa.String(length=32), primary_key=True, nullable=False),
    sa.Column('product_id', sa.String(length=32), sa.ForeignKey('products.id', ondelete=None), primary_key=False, nullable=False),
    sa.Column('seller_id', sa.String(length=32), sa.ForeignKey('sellers.id', ondelete=None), primary_key=False, nullable=False),
    sa.Column('pavilion_id', sa.String(length=32), sa.ForeignKey('pavilions.id', ondelete=None), primary_key=False, nullable=False),
    sa.Column('price', sa.Integer(), primary_key=False, nullable=False),
    sa.Column('wholesale', sa.Boolean(), primary_key=False, nullable=False),
    sa.Column('retail', sa.Boolean(), primary_key=False, nullable=False),
    sa.Column('status', sa.String(length=16), primary_key=False, nullable=False),
    sa.Column('offer_id', sa.String(length=32), sa.ForeignKey('offers.id', ondelete=None), primary_key=False, nullable=True),
    sa.Column('note', sa.Text(), primary_key=False, nullable=False),
    sa.UniqueConstraint('offer_id', name=None),
    sa.UniqueConstraint('product_id', 'pavilion_id', name='uq_merchant_product_pavilion'),
)
sa.Index('ix_merchant_listings_product_id', metadata.tables['merchant_listings'].c['product_id'], unique=False)
sa.Index('ix_merchant_listings_seller_id', metadata.tables['merchant_listings'].c['seller_id'], unique=False)

sa.Table('offer_sale_modes', metadata,
    sa.Column('offer_id', sa.String(length=32), sa.ForeignKey('offers.id', ondelete='CASCADE'), primary_key=True, nullable=False),
    sa.Column('wholesale', sa.Boolean(), primary_key=False, nullable=False),
    sa.Column('retail', sa.Boolean(), primary_key=False, nullable=False),
)

sa.Table('seller_review_reports_v082', metadata,
    sa.Column('id', sa.String(length=32), primary_key=True, nullable=False),
    sa.Column('buyer', sa.String(length=32), sa.ForeignKey('buyers.id', ondelete=None), primary_key=False, nullable=False),
    sa.Column('review_id', sa.String(length=32), sa.ForeignKey('seller_reviews_v082.id', ondelete=None), primary_key=False, nullable=False),
    sa.Column('reason', sa.String(length=200), primary_key=False, nullable=False),
    sa.Column('created_at', sa.Float(), primary_key=False, nullable=False),
    sa.UniqueConstraint('buyer', 'review_id', name='uq_v082_review_report'),
)
sa.Index('ix_seller_review_reports_v082_buyer', metadata.tables['seller_review_reports_v082'].c['buyer'], unique=False)
sa.Index('ix_seller_review_reports_v082_review_id', metadata.tables['seller_review_reports_v082'].c['review_id'], unique=False)

